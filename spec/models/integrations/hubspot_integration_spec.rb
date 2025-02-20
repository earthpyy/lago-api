# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::HubspotIntegration, type: :model do
  subject(:hubspot_integration) { build(:hubspot_integration) }

  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:connection_id) }
  it { is_expected.to validate_presence_of(:private_app_token) }
  it { is_expected.to validate_presence_of(:default_targeted_object) }

  describe 'validations' do
    it 'validates uniqueness of the code' do
      expect(hubspot_integration).to validate_uniqueness_of(:code).scoped_to(:organization_id)
    end
  end

  describe '#connection_id' do
    it 'assigns and retrieve a secret pair' do
      hubspot_integration.connection_id = 'connection_id'
      expect(hubspot_integration.connection_id).to eq('connection_id')
    end
  end

  describe '#private_app_token' do
    it 'assigns and retrieve a secret pair' do
      hubspot_integration.private_app_token = 'secret_token'
      expect(hubspot_integration.private_app_token).to eq('secret_token')
    end
  end

  describe '#default_targeted_object' do
    it 'assigns and retrieve a setting' do
      hubspot_integration.default_targeted_object = 'Companies'
      expect(hubspot_integration.default_targeted_object).to eq('Companies')
    end
  end

  describe '#sync_invoices' do
    it 'assigns and retrieve a setting' do
      hubspot_integration.sync_invoices = true
      expect(hubspot_integration.sync_invoices).to eq(true)
    end
  end

  describe '#sync_subscriptions' do
    it 'assigns and retrieve a setting' do
      hubspot_integration.sync_subscriptions = true
      expect(hubspot_integration.sync_subscriptions).to eq(true)
    end
  end
end
