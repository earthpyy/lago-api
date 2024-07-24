# frozen_string_literal: true

module Events
  class PostProcessService < BaseService
    def initialize(event:)
      @organization = event.organization
      @event = event
      super
    end

    def call
      event.external_customer_id ||= customer&.external_id

      unless event.external_subscription_id
        Deprecation.report('event_missing_external_subscription_id', organization.id)
      end

      # NOTE: prevent subscription if more than 1 subscription is active
      #       if multiple terminated matches the timestamp, takes the most recent
      if !event.external_subscription_id && subscriptions.count(&:active?) <= 1
        event.external_subscription_id ||= subscriptions.first&.external_id
      end

      event.save!

      expire_cached_charges(subscriptions)
      pre_aggregate_event unless handle_pay_in_advance

      result.event = event
      result
    rescue ActiveRecord::RecordInvalid => e
      deliver_error_webhook(error: e.record.errors.messages)

      result
    rescue ActiveRecord::RecordNotUnique
      deliver_error_webhook(error: {transaction_id: ['value_already_exist']})

      result
    end

    private

    attr_reader :event

    delegate :organization, to: :event

    def customer
      return @customer if defined? @customer

      @customer = organization.subscriptions.find_by(external_id: event.external_subscription_id)&.customer
    end

    def subscriptions
      return @subscriptions if defined? @subscriptions

      subscriptions = if customer && event.external_subscription_id.blank?
        customer.subscriptions
      else
        organization.subscriptions.where(external_id: event.external_subscription_id)
      end
      return unless subscriptions

      @subscriptions = subscriptions
        .where("date_trunc('millisecond', started_at::timestamp) <= ?::timestamp", event.timestamp)
        .where(
          "terminated_at IS NULL OR date_trunc('millisecond', terminated_at::timestamp) >= ?",
          event.timestamp
        )
        .order('terminated_at DESC NULLS FIRST, started_at DESC')
    end

    def billable_metric
      @billable_metric ||= organization.billable_metrics.find_by(code: event.code)
    end

    def expire_cached_charges(subscriptions)
      active_subscription = subscriptions.select(&:active?)
      return if active_subscription.blank?
      return unless billable_metric

      charges = billable_metric.charges
        .joins(:plan)
        .where(plans: {id: active_subscription.map(&:plan_id)})

      charges.each do |charge|
        active_subscription.each do |subscription|
          Subscriptions::ChargeCacheService.new(subscription:, charge:).expire_cache
        end
      end
    end

    def handle_pay_in_advance
      return false unless billable_metric
      return false unless in_advance_charges.any?

      Events::PayInAdvanceJob.perform_later(Events::CommonFactory.new_instance(source: event).as_json)
      true
    end

    def in_advance_charges
      return Charge.none unless subscriptions.first

      subscriptions
        .first
        .plan
        .charges
        .pay_in_advance
        .joins(:billable_metric)
        .where(billable_metric: {code: event.code})
    end

    def applicable_charges
    end

    def deliver_error_webhook(error:)
      SendWebhookJob.perform_later('event.error', event, {error:})
    end

    def pre_aggregate_event
      return if billable_metric.recurring?
      return unless billable_metric.sum_agg?

      # SUM aggregation
      aggregation_property = billable_metric.field_name
      return unless event.properties.key?(aggregation_property)

      pre_aggregation = PreAggregation.find_or_create_by(
        organization_id: event.organization_id,
        external_subscription_id: event.external_subscription_id,
        code: event.code,
        filters: event.properties.except(aggregation_property),
        timestamp: event.timestamp.utc.beginning_of_hour
      )

      event_value = BigDecimal(event.properties[aggregation_property])

      pre_aggregation.with_lock do
        pre_aggregated_value = BigDecimal(pre_aggregation.aggregated_value)
        pre_aggregation.update!(
          aggregated_value: pre_aggregated_value + event_value,
          units: pre_aggregation.units + 1
        )
      end
    end
  end
end
