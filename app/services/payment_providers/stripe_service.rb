# frozen_string_literal: true

module PaymentProviders
  class StripeService < BaseService
    PAYMENT_SERVICE_CLASS_MAP = {
      "Invoice" => Invoices::Payments::StripeService,
      "PaymentRequest" => PaymentRequests::Payments::StripeService
    }.freeze

    def create_or_update(**args)
      payment_provider_result = PaymentProviders::FindService.call(
        organization_id: args[:organization_id],
        code: args[:code],
        id: args[:id],
        payment_provider_type: 'stripe'
      )

      stripe_provider = if payment_provider_result.success?
        payment_provider_result.payment_provider
      else
        PaymentProviders::StripeProvider.new(
          organization_id: args[:organization_id],
          code: args[:code]
        )
      end

      secret_key = stripe_provider.secret_key

      stripe_provider.secret_key = args[:secret_key] if args.key?(:secret_key)
      stripe_provider.code = args[:code] if args.key?(:code)
      stripe_provider.name = args[:name] if args.key?(:name)
      stripe_provider.success_redirect_url = args[:success_redirect_url] if args.key?(:success_redirect_url)
      stripe_provider.save!

      if secret_key != stripe_provider.secret_key
        unregister_webhook(stripe_provider, secret_key)

        PaymentProviders::Stripe::RegisterWebhookJob.perform_later(stripe_provider)

        # NOTE: ensure existing payment_provider_customers are
        #       attached to the provider
        reattach_provider_customers(
          organization_id: args[:organization_id],
          stripe_provider:
        )
      end

      result.stripe_provider = stripe_provider
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def refresh_webhook(stripe_provider:)
      unregister_webhook(stripe_provider, stripe_provider.secret_key)
      PaymentProviders::Stripe::RegisterWebhookService.call(stripe_provider)
    end

    def handle_incoming_webhook(organization_id:, params:, signature:, code: nil)
      organization = Organization.find_by(id: organization_id)

      payment_provider_result = PaymentProviders::FindService.call(
        organization_id:,
        code:,
        payment_provider_type: 'stripe'
      )

      return payment_provider_result unless payment_provider_result.success?

      event = ::Stripe::Webhook.construct_event(
        params,
        signature,
        payment_provider_result.payment_provider&.webhook_secret
      )

      PaymentProviders::Stripe::HandleEventJob.perform_later(
        organization:,
        event: event.to_json
      )

      result.event = event
      result
    rescue JSON::ParserError
      result.service_failure!(code: 'webhook_error', message: 'Invalid payload')
    rescue ::Stripe::SignatureVerificationError
      result.service_failure!(code: 'webhook_error', message: 'Invalid signature')
    end

    def handle_event(organization:, event_json:)
      event = ::Stripe::Event.construct_from(JSON.parse(event_json))
      unless PaymentProviders::StripeProvider::WEBHOOKS_EVENTS.include?(event.type)
        Rails.logger.warn("Unexpected stripe event type: #{event.type}")
        return result
      end

      case event.type
      when 'setup_intent.succeeded'
        service = PaymentProviderCustomers::StripeService.new

        service
          .update_provider_default_payment_method(
            organization_id: organization.id,
            stripe_customer_id: event.data.object.customer,
            payment_method_id: event.data.object.payment_method,
            metadata: event.data.object.metadata.to_h.symbolize_keys
          ).raise_if_error!

        service
          .update_payment_method(
            organization_id: organization.id,
            stripe_customer_id: event.data.object.customer,
            payment_method_id: event.data.object.payment_method,
            metadata: event.data.object.metadata.to_h.symbolize_keys
          ).raise_if_error!
      when 'customer.updated'
        payment_method_id = event.data.object.invoice_settings.default_payment_method ||
          event.data.object.default_source

        PaymentProviderCustomers::StripeService
          .new
          .update_payment_method(
            organization_id: organization.id,
            stripe_customer_id: event.data.object.id,
            payment_method_id:,
            metadata: event.data.object.metadata.to_h.symbolize_keys
          ).raise_if_error!
      when 'charge.succeeded'
        payment_service_klass(event)
          .new.update_payment_status(
            organization_id: organization.id,
            provider_payment_id: event.data.object.payment_intent,
            status: 'succeeded',
            metadata: event.data.object.metadata.to_h.symbolize_keys
          ).raise_if_error!
      when 'charge.dispute.closed'
        PaymentProviders::Webhooks::Stripe::ChargeDisputeClosedService.call(
          organization_id: organization.id,
          event_json:
        ).raise_if_error!
      when 'payment_intent.payment_failed', 'payment_intent.succeeded'
        status = (event.type == 'payment_intent.succeeded') ? 'succeeded' : 'failed'
        payment_service_klass(event)
          .new.update_payment_status(
            organization_id: organization.id,
            provider_payment_id: event.data.object.id,
            status:,
            metadata: event.data.object.metadata.to_h.symbolize_keys
          ).raise_if_error!
      when 'payment_method.detached'
        PaymentProviderCustomers::StripeService
          .new
          .delete_payment_method(
            organization_id: organization.id,
            stripe_customer_id: event.data.object.customer,
            payment_method_id: event.data.object.id,
            metadata: event.data.object.metadata.to_h.symbolize_keys
          ).raise_if_error!
      when 'charge.refund.updated'
        CreditNotes::Refunds::StripeService
          .new.update_status(
            provider_refund_id: event.data.object.id,
            status: event.data.object.status,
            metadata: event.data.object.metadata.to_h.symbolize_keys
          )
      end
    rescue BaseService::NotFoundFailure => e
      # NOTE: Error with stripe sandbox should be ignord
      raise if event.livemode

      Rails.logger.warn("Stripe resource not found: #{e.message}. JSON: #{event_json}")
      BaseService::Result.new # NOTE: Prevents error from being re-raised
    end

    private

    def unregister_webhook(stripe_provider, api_key)
      return if stripe_provider.webhook_id.blank?

      ::Stripe::WebhookEndpoint.delete(
        stripe_provider.webhook_id, {}, {api_key:}
      )
    rescue => e
      # NOTE: Since removing the webbook end-point is not critical
      #       we don't want any error with it to break the update of the
      #       payment provider
      Rails.logger.error(e.message)
      Rails.logger.error(e.backtrace.join("\n"))

      Sentry.capture_exception(e)
    end

    def reattach_provider_customers(organization_id:, stripe_provider:)
      PaymentProviderCustomers::StripeCustomer
        .joins(:customer)
        .where(payment_provider_id: nil, customers: {organization_id:})
        .update_all(payment_provider_id: stripe_provider.id) # rubocop:disable Rails/SkipsModelValidations
    end

    def payment_service_klass(event)
      payable_type = event.data.object.metadata.to_h[:lago_payable_type] || "Invoice"

      PAYMENT_SERVICE_CLASS_MAP.fetch(payable_type) do
        raise NameError, "Invalid lago_payable_type: #{payable_type}"
      end
    end
  end
end
