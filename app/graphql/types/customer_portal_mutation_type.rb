# frozen_string_literal: true

module Types
  class CustomerPortalMutationType < Types::BaseObject
    field :download_customer_portal_invoice, mutation: Mutations::CustomerPortal::DownloadInvoice
  end
end
