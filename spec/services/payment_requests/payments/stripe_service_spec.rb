# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentRequests::Payments::StripeService, type: :service do
  subject(:stripe_service) { described_class.new(payment_request) }

  let(:customer) { create(:customer, payment_provider_code: code) }
  let(:organization) { customer.organization }
  let(:stripe_payment_provider) { create(:stripe_provider, organization:, code:) }
  let(:stripe_customer) {
    create(:stripe_customer, customer:, payment_method_id: stripe_payment_method_id)
  }
  let(:stripe_payment_method_id) { "pm_123456" }
  let(:code) { "stripe_1" }

  let(:payment_request) do
    create(
      :payment_request,
      organization:,
      customer:,
      amount_cents: 799,
      amount_currency: "EUR",
      invoices: [invoice_1, invoice_2]
    )
  end

  let(:invoice_1) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 200,
      currency: 'EUR',
      ready_for_payment_processing: true
    )
  end

  let(:invoice_2) do
    create(
      :invoice,
      organization:,
      customer:,
      total_amount_cents: 599,
      currency: 'EUR',
      ready_for_payment_processing: true
    )
  end

  describe ".create" do
    let(:provider_customer_service) { instance_double(PaymentProviderCustomers::StripeService) }

    let(:provider_customer_service_result) do
      BaseService::Result.new.tap do |result|
        result.payment_method = Stripe::PaymentMethod.new(id: "pm_123456")
      end
    end

    let(:customer_response) do
      File.read(Rails.root.join("spec/fixtures/stripe/customer_retrieve_response.json"))
    end

    let(:payment_status) { "succeeded" }

    before do
      stripe_payment_provider
      stripe_customer

      allow(Stripe::PaymentIntent).to receive(:create)
        .and_return(
          Stripe::PaymentIntent.construct_from(
            id: "ch_123456",
            status: payment_status,
            amount: payment_request.total_amount_cents,
            currency: payment_request.currency
          )
        )
      allow(SegmentTrackJob).to receive(:perform_later)
      allow(PaymentProviderCustomers::StripeService).to receive(:new)
        .and_return(provider_customer_service)
      allow(provider_customer_service).to receive(:check_payment_method)
        .and_return(provider_customer_service_result)

      stub_request(:get, "https://api.stripe.com/v1/customers/#{stripe_customer.provider_customer_id}")
        .to_return(status: 200, body: customer_response, headers: {})
    end

    it "creates a stripe payment and a payment", :aggregate_failures do
      result = stripe_service.create

      expect(result).to be_success

      expect(result.payable).to be_payment_succeeded
      expect(result.payable.payment_attempts).to eq(1)
      expect(result.payable.ready_for_payment_processing).to eq(false)

      expect(result.payment.id).to be_present
      expect(result.payment.payable).to eq(payment_request)
      expect(result.payment.payment_provider).to eq(stripe_payment_provider)
      expect(result.payment.payment_provider_customer).to eq(stripe_customer)
      expect(result.payment.amount_cents).to eq(payment_request.total_amount_cents)
      expect(result.payment.amount_currency).to eq(payment_request.currency)
      expect(result.payment.status).to eq("succeeded")

      expect(Stripe::PaymentIntent).to have_received(:create).with(
        {
          amount: payment_request.total_amount_cents,
          currency: payment_request.currency.downcase,
          customer: customer.stripe_customer.provider_customer_id,
          payment_method: stripe_payment_method_id,
          payment_method_types: customer.stripe_customer.provider_payment_methods,
          confirm: true,
          off_session: true,
          error_on_requires_action: true,
          description: "#{organization.name} - PaymentRequest 123",
          metadata: {
            lago_customer_id: customer.id,
            lago_payment_request_id: payment_request.id,
            lago_invoice_ids: payment_request.invoice_ids
          }
        },
        hash_including(
          {
            api_key: an_instance_of(String),
            idempotency_key: "#{payment_request.id}/#{payment_request.reload.payment_attempts}"
          }
        )
      )
    end

    it "updates invoice payment status to succeeded", :aggregate_failures do
      stripe_service.create

      expect(invoice_1.reload).to be_payment_succeeded
      expect(invoice_2.reload).to be_payment_succeeded
    end

    context "with no payment provider" do
      let(:stripe_payment_provider) { nil }

      it "does not creates a stripe payment", :aggregate_failures do
        result = stripe_service.create

        expect(result).to be_success

        expect(result.payable).to eq(payment_request)
        expect(result.payment).to be_nil

        expect(Stripe::PaymentIntent).not_to have_received(:create)
      end
    end

    context 'with 0 amount' do
      let(:payment_request) do
        create(
          :payment_request,
          organization:,
          customer:,
          amount_cents: 0,
          amount_currency: "EUR",
          invoices: [invoice]
        )
      end

      let(:invoice) do
        create(
          :invoice,
          organization:,
          customer:,
          total_amount_cents: 0,
          currency: 'EUR'
        )
      end

      it 'does not creates a stripe payment', :aggregate_failures do
        result = stripe_service.create

        expect(result).to be_success
        expect(result.payable).to eq(payment_request)
        expect(result.payment).to be_nil
        expect(result.payable).to be_payment_succeeded
        expect(Stripe::PaymentIntent).not_to have_received(:create)
      end
    end

    context "when customer does not have a provider customer id" do
      before { stripe_customer.update!(provider_customer_id: nil) }

      it "does not creates a stripe payment", :aggregate_failures do
        result = stripe_service.create

        expect(result).to be_success

        expect(result.payable).to eq(payment_request)
        expect(result.payment).to be_nil

        expect(Stripe::PaymentIntent).not_to have_received(:create)
      end
    end

    context "when customer does not have a payment method" do
      let(:stripe_customer) { create(:stripe_customer, customer:) }

      before do
        allow(Stripe::Customer).to receive(:retrieve)
          .and_return(Stripe::StripeObject.construct_from(
            {
              invoice_settings: {
                default_payment_method: nil
              },
              default_source: nil
            }
          ))

        allow(Stripe::PaymentMethod).to receive(:list)
          .and_return(Stripe::ListObject.construct_from(
            data: [
              {
                id: "pm_123456",
                object: "payment_method",
                card: {brand: "visa"},
                created: 1_656_422_973,
                customer: "cus_123456",
                livemode: false,
                metadata: {},
                type: "card"
              }
            ]
          ))
      end

      it "retrieves the payment method" do
        result = stripe_service.create

        expect(result).to be_success
        expect(customer.stripe_customer.reload).to be_present
        expect(customer.stripe_customer.provider_customer_id).to eq(stripe_customer.provider_customer_id)
        expect(customer.stripe_customer.payment_method_id).to eq("pm_123456")

        expect(Stripe::PaymentMethod).to have_received(:list)
        expect(Stripe::PaymentIntent).to have_received(:create)
      end
    end

    context "with card error on stripe" do
      let(:customer) { create(:customer, organization:, payment_provider_code: code) }

      let(:organization) do
        create(:organization, webhook_url: "https://webhook.com")
      end

      before do
        allow(Stripe::PaymentIntent).to receive(:create)
          .and_raise(Stripe::CardError.new("error", {}))
        allow(PaymentRequests::Payments::DeliverErrorWebhookService)
          .to receive(:call_async)
          .and_call_original
      end

      it "delivers an error webhook" do
        stripe_service.create

        expect(PaymentRequests::Payments::DeliverErrorWebhookService).to have_received(:call_async)
        expect(SendWebhookJob).to have_been_enqueued
          .with(
            "payment_request.payment_failure",
            payment_request,
            provider_customer_id: stripe_customer.provider_customer_id,
            provider_error: {
              message: "error",
              error_code: nil
            }
          )
      end

      it "marks the payment request as payment failed" do
        stripe_service.create
        expect(payment_request.reload).to be_payment_failed
      end
    end

    context "when payment request has a too small amount" do
      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }

      let(:payment_request) do
        create(
          :payment_request,
          organization:,
          customer:,
          amount_cents: 20,
          amount_currency: "EUR",
          ready_for_payment_processing: true
        )
      end

      before do
        allow(Stripe::PaymentIntent).to receive(:create)
          .and_raise(Stripe::InvalidRequestError.new("amount_too_small", {}, code: "amount_too_small"))
      end

      it "does not mark the payment request as failed" do
        stripe_service.create
        expect(payment_request.reload).to be_payment_pending
      end
    end

    context "with random stripe error" do
      let(:customer) { create(:customer, organization:, payment_provider_code: code) }

      let(:organization) do
        create(:organization, webhook_url: "https://webhook.com")
      end

      let(:stripe_error) { Stripe::StripeError.new("error") }

      before do
        allow(Stripe::PaymentIntent).to receive(:create)
          .and_raise(stripe_error)
        allow(PaymentRequests::Payments::DeliverErrorWebhookService)
          .to receive(:call_async)
          .and_call_original
      end

      it "delivers an error webhook and raises the error" do
        expect { stripe_service.create }
          .to raise_error(stripe_error)
          .and not_change { payment_request.reload.payment_status }

        expect(PaymentRequests::Payments::DeliverErrorWebhookService).to have_received(:call_async)
        expect(SendWebhookJob).to have_been_enqueued
          .with(
            "payment_request.payment_failure",
            payment_request,
            provider_customer_id: stripe_customer.provider_customer_id,
            provider_error: {
              message: "error",
              error_code: nil
            }
          )
      end
    end

    context "when payment status is processing" do
      let(:payment_status) { "processing" }

      it "creates a stripe payment and a payment", :aggregate_failures do
        result = stripe_service.create

        expect(result).to be_success

        expect(result.payable).to be_payment_pending
        expect(result.payable.payment_attempts).to eq(1)
        expect(result.payable.ready_for_payment_processing).to eq(false)

        expect(result.payment.id).to be_present
        expect(result.payment.payable).to eq(payment_request)
        expect(result.payment.payment_provider).to eq(stripe_payment_provider)
        expect(result.payment.payment_provider_customer).to eq(stripe_customer)
        expect(result.payment.amount_cents).to eq(payment_request.total_amount_cents)
        expect(result.payment.amount_currency).to eq(payment_request.currency)
        expect(result.payment.status).to eq("processing")

        expect(Stripe::PaymentIntent).to have_received(:create)
      end
    end
  end
end