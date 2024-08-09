# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Fees::CreatePayInAdvanceService, type: :service do
  subject(:fee_service) {
    described_class.new(charge:, event:, billing_at: event.timestamp, estimate:)
  }

  let(:organization) { create(:organization) }

  let(:billable_metric) {
    create(:sum_billable_metric, organization:, field_name: 'units')
  }

  let(:customer) { create(:customer, organization:) }

  let(:plan_1) { create(:plan, organization:, amount_cents: 0) }
  let(:plan_2) { create(:plan, organization:, amount_cents: 0) }
  let(:plan_3) { create(:plan, organization:, amount_cents: 0) }
  let(:plan_4) { create(:plan, organization:, amount_cents: 0) }

  let(:subscription_external_id) { SecureRandom.uuid }

  let(:subscription_1) {
    create(
      :subscription,
      :terminated,
      customer:,
      plan: plan_1,
      terminated_at: Time.parse("2024-08-01T12:40:02Z"),
      started_at: Time.parse("2024-08-01T09:26:08Z"),
      billing_time: "calendar",
      subscription_at: Time.parse("2024-08-01T09:26:08Z"),
      external_id: subscription_external_id,
      previous_subscription: nil,
    )
  }

  let(:subscription_2) {
    create(
      :subscription,
      :terminated,
      customer:,
      plan: plan_2,
      terminated_at: Time.parse("2024-08-02T13:13:01Z"),
      started_at: Time.parse("2024-08-02T12:55:41Z"),
      billing_time: "calendar",
      subscription_at: Time.parse("2024-08-01T09:26:08Z"),
      external_id: subscription_external_id,
      previous_subscription: subscription_1
    )
  }

  let(:subscription_3) {
    create(
      :subscription,
      :terminated,
      customer:,
      plan: plan_3,
      terminated_at: Time.parse("2024-08-02T12:55:41Z"),
      started_at: Time.parse("2024-08-02T12:40:02Z"),
      billing_time: "calendar",
      subscription_at: Time.parse("2024-08-01T09:26:08Z"),
      external_id: subscription_external_id,
      previous_subscription: subscription_2
    )
  }

  let(:subscription_4) {
    create(
      :subscription,
      :active,
      customer:,
      plan: plan_4,
      terminated_at: nil,
      started_at: Time.parse("2024-08-02T13:13:01Z"),
      billing_time: "calendar",
      subscription_at: Time.parse("2024-08-01T09:26:08Z"),
      external_id: subscription_external_id,
      previous_subscription: subscription_2
    )
  }

  let(:tax) { create(:tax, organization:, rate: 0.0, applied_to_organization: false) }

  let(:charge_filter) { nil }

  let(:charge) {
    create(
      :percentage_charge,
      :pay_in_advance,
      billable_metric:,
      plan: plan_3,
      amount_currency: nil,
      properties: {
        "rate"=>"10",
        "fixed_amount"=>"0",
        "per_transaction_max_amount"=>"100",
        "per_transaction_min_amount" => nil
      },
      min_amount_cents: 0,
      invoiceable: false,
      prorated: false,
      regroup_paid_fees: "invoice"
    )
  }

  let(:estimate) { false }

  let(:event_1) do
    Events::CommonFactory.new_instance(
      source: create(
        :event,
        external_subscription_id: subscription_external_id,
        external_customer_id: customer.external_id,
        organization_id: organization.id,
        properties: {"units"=>"345"},
        timestamp: Time.parse("2024-08-15T22:00:00Z")
      )
    )
  end

  let(:event_2) do
    Events::CommonFactory.new_instance(
      source: create(
        :event,
        external_subscription_id: subscription_external_id,
        external_customer_id: customer.external_id,
        organization_id: organization.id,
        properties: {"units"=>"1235"},
        timestamp: Time.parse("2024-08-15T22:00:00Z")
      )
    )
  end

  let(:event_3) do
    Events::CommonFactory.new_instance(
      source: create(
        :event,
        external_subscription_id: subscription_external_id,
        external_customer_id: customer.external_id,
        organization_id: organization.id,
        properties: {"units"=>"455"},
        timestamp: Time.parse("2024-08-02T12:42:40Z")
      )
    )
  end

  let(:event_4) do
    Events::CommonFactory.new_instance(
      source: create(
        :event,
        external_subscription_id: subscription_external_id,
        external_customer_id: customer.external_id,
        organization_id: organization.id,
        properties: {"units"=>"1235"},
        timestamp: Time.parse("2024-08-02T12:42:35Z")
      )
    )
  end

  let(:event_5) do
    Events::CommonFactory.new_instance(
      source: create(
        :event,
        external_subscription_id: subscription_external_id,
        external_customer_id: customer.external_id,
        organization_id: organization.id,
        properties: {"units"=>"125"},
        timestamp: Time.parse("2024-08-02T13:09:04Z")
      )
    )
  end

  let(:event_6) do
    Events::CommonFactory.new_instance(
      source: create(
        :event,
        external_subscription_id: subscription_external_id,
        external_customer_id: customer.external_id,
        organization_id: organization.id,
        properties: {"units"=>"2250"},
        timestamp: Time.parse("2024-08-02T13:16:58Z")
      )
    )
  end

  let(:event_7) do
    Events::CommonFactory.new_instance(
      source: create(
        :event,
        external_subscription_id: subscription_external_id,
        external_customer_id: customer.external_id,
        organization_id: organization.id,
        properties: {"units"=>"225"},
        timestamp: Time.parse("2024-08-02T13:16:53Z")
      )
    )
  end

  let(:event_8) do
    Events::CommonFactory.new_instance(
      source: create(
        :event,
        external_subscription_id: subscription_external_id,
        external_customer_id: customer.external_id,
        organization_id: organization.id,
        properties: {"units"=>"150"},
        timestamp: Time.parse("2024-08-06T15:01:49Z")
      )
    )
  end

  let(:event_properties) { {} }

  let(:event) { event_1 }

  before do
    tax

    subscription_1
    subscription_2
    subscription_3
    subscription_4

    event_1
    event_2
    event_3
    event_4

    # these events where not created in prod DB when the invoice fee was calculated.
    #event_5
    #event_6
    #event_7
    #event_8
  end

  describe '#call' do
    let(:aggregation_result) do
      BaseService::Result.new.tap do |result|
        result.aggregation = 9
        result.count = 4
        result.options = {}
      end
    end

    let(:charge_result) do
      BaseService::Result.new.tap do |result|
        result.amount = 10
        result.unit_amount = 0.01111111111
        result.count = 1
        result.units = 9
      end
    end

    before do
      #allow(Charges::PayInAdvanceAggregationService).to receive(:call)
      #  .with(charge:, boundaries: Hash, properties: Hash, event:, charge_filter:)
      #  .and_return(aggregation_result)

      #allow(Charges::ApplyPayInAdvanceChargeModelService).to receive(:call)
      #  .with(charge:, aggregation_result:, properties: Hash)
      #  .and_return(charge_result)
    end

    it 'creates a fee' do
      result_1 = described_class.new(charge:, event: event_1, billing_at: event_1.timestamp, estimate:).call
      result_2 = described_class.new(charge:, event: event_2, billing_at: event_2.timestamp, estimate:).call
      result_3 = described_class.new(charge:, event: event_3, billing_at: event_3.timestamp, estimate:).call
      result_4 = described_class.new(charge:, event: event_4, billing_at: event_4.timestamp, estimate:).call

      binding.break

      aggregate_failures do
        expect(result).to be_success

        expect(result.fees.count).to eq(1)
        expect(result.fees.first).to have_attributes(
          subscription:,
          charge:,
          amount_cents: 10,
          amount_currency: 'EUR',
          fee_type: 'charge',
          pay_in_advance: true,
          invoiceable: charge,
          units: 9,
          properties: Hash,
          events_count: 1,
          charge_filter: nil,
          pay_in_advance_event_id: event.id,
          pay_in_advance_event_transaction_id: event.transaction_id,
          payment_status: 'pending',
          unit_amount_cents: 1,
          precise_unit_amount: 0.01111111111,

          taxes_rate: 20.0,
          taxes_amount_cents: 2
        )
        expect(result.fees.first.applied_taxes.count).to eq(1)
      end
    end

    it 'delivers a webhook' do
      fee_service.call

      expect(SendWebhookJob).to have_been_enqueued
        .with('fee.created', Fee)
    end

    context 'when aggregation fails' do
      let(:aggregation_result) do
        BaseService::Result.new.service_failure!(code: 'failure', message: 'Failure')
      end

      it 'returns a failure' do
        result = fee_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq('failure')
          expect(result.error.error_message).to eq('Failure')
        end
      end
    end

    context 'when charge model fails' do
      let(:charge_result) do
        BaseService::Result.new.service_failure!(code: 'failure', message: 'Failure')
      end

      it 'returns a failure' do
        result = fee_service.call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ServiceFailure)
          expect(result.error.code).to eq('failure')
          expect(result.error.error_message).to eq('Failure')
        end
      end
    end

    context 'when charge has a charge filter' do
      let(:event_properties) do
        {
          payment_method: 'card',
          card_location: 'domestic',
          scheme: 'visa',
          card_type: 'credit'
        }
      end

      let(:card_location) do
        create(:billable_metric_filter, billable_metric:, key: 'card_location', values: %i[domestic])
      end
      let(:scheme) { create(:billable_metric_filter, billable_metric:, key: 'scheme', values: %i[visa mastercard]) }

      let(:filter) { create(:charge_filter, charge:) }
      let(:filter_values) do
        [
          create(
            :charge_filter_value,
            values: ['domestic'],
            billable_metric_filter: card_location,
            charge_filter: filter
          ),
          create(
            :charge_filter_value,
            values: %w[visa mastercard],
            billable_metric_filter: scheme,
            charge_filter: filter
          )
        ]
      end

      let(:charge_filter) { filter }

      before { filter_values }

      it 'creates a fee' do
        result = fee_service.call

        expect(result).to be_success

        expect(result.fees.count).to eq(1)
        expect(result.fees.first).to have_attributes(
          subscription:,
          charge:,
          amount_cents: 10,
          amount_currency: 'EUR',
          fee_type: 'charge',
          pay_in_advance: true,
          invoiceable: charge,
          units: 9,
          properties: Hash,
          events_count: 1,
          charge_filter:,
          pay_in_advance_event_id: event.id,
          pay_in_advance_event_transaction_id: event.transaction_id,
          unit_amount_cents: 1,
          precise_unit_amount: 0.01111111111,

          taxes_rate: 20.0,
          taxes_amount_cents: 2
        )
        expect(result.fees.first.applied_taxes.count).to eq(1)
      end

      context 'when event does not match the charge filter' do
        let(:charge_filter) { ChargeFilter }

        let(:event_properties) do
          {
            payment_method: 'card',
            card_location: 'international',
            scheme: 'visa',
            card_type: 'credit'
          }
        end

        it 'creates a fee' do
          result = fee_service.call

          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 10,
            amount_currency: 'EUR',
            fee_type: 'charge',
            pay_in_advance: true,
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            charge_filter_id: nil,
            pay_in_advance_event_id: event.id,
            pay_in_advance_event_transaction_id: event.transaction_id,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01111111111,

            taxes_rate: 20.0,
            taxes_amount_cents: 2
          )
          expect(result.fees.first.applied_taxes.count).to eq(1)
        end
      end
    end

    context 'when charge has a grouped_by property' do
      let(:charge) do
        create(
          :standard_charge,
          billable_metric:,
          pay_in_advance: true,
          properties: {'grouped_by' => ['operator'], 'amount' => '100'}
        )
      end

      let(:event) do
        Events::CommonFactory.new_instance(
          source: create(
            :event,
            organization:,
            external_subscription_id: subscription.external_id,
            properties: {'operator' => 'foo'}
          )
        )
      end

      it 'creates a fee' do
        result = fee_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 10,
            amount_currency: 'EUR',
            fee_type: 'charge',
            pay_in_advance: true,
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            pay_in_advance_event_id: event.id,
            pay_in_advance_event_transaction_id: event.transaction_id,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01111111111,
            grouped_by: {'operator' => 'foo'},

            taxes_rate: 20.0,
            taxes_amount_cents: 2
          )
          expect(result.fees.first.applied_taxes.count).to eq(1)
        end
      end
    end

    context 'when in estimate mode' do
      let(:estimate) { true }

      it 'does not persist the fee' do
        result = fee_service.call

        aggregate_failures do
          expect(result).to be_success

          expect(result.fees.count).to eq(1)
          expect(result.fees.first).not_to be_persisted
          expect(result.fees.first).to have_attributes(
            subscription:,
            charge:,
            amount_cents: 10,
            amount_currency: 'EUR',
            fee_type: 'charge',
            pay_in_advance: true,
            invoiceable: charge,
            units: 9,
            properties: Hash,
            events_count: 1,
            pay_in_advance_event_id: event.id,
            pay_in_advance_event_transaction_id: event.transaction_id,
            unit_amount_cents: 1,
            precise_unit_amount: 0.01111111111,

            taxes_rate: 20.0,
            taxes_amount_cents: 2
          )
          expect(result.fees.first.applied_taxes.size).to eq(1)
        end
      end

      it 'does not deliver a webhook' do
        fee_service.call

        expect(SendWebhookJob).not_to have_been_enqueued
          .with('fee.created', Fee)
      end
    end

    context 'when in current and max aggregation result' do
      let(:aggregation_result) do
        BaseService::Result.new.tap do |result|
          result.amount = 10
          result.count = 1
          result.units = 9
          result.current_aggregation = 9
          result.max_aggregation = 9
          result.max_aggregation_with_proration = nil
        end
      end

      it 'creates a cached aggregation' do
        aggregate_failures do
          expect { fee_service.call }.to change(CachedAggregation, :count).by(1)

          cached_aggregation = CachedAggregation.last
          expect(cached_aggregation.organization_id).to eq(organization.id)
          expect(cached_aggregation.event_id).to eq(event.id)
          expect(cached_aggregation.timestamp.iso8601(3)).to eq(event.timestamp.iso8601(3))
          expect(cached_aggregation.charge_id).to eq(charge.id)
          expect(cached_aggregation.external_subscription_id).to eq(event.external_subscription_id)
          expect(cached_aggregation.charge_filter_id).to be_nil
          expect(cached_aggregation.current_aggregation).to eq(9)
          expect(cached_aggregation.current_amount).to be_nil
          expect(cached_aggregation.max_aggregation).to eq(9)
          expect(cached_aggregation.max_aggregation_with_proration).to be_nil
          expect(cached_aggregation.grouped_by).to eq({})
        end
      end
    end
  end
end
