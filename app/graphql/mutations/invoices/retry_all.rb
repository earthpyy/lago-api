# frozen_string_literal: true

module Mutations
  module Invoices
    class RetryAll < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'invoices:update'

      graphql_name 'RetryAllInvoices'
      description 'Retry all failed invoices'

      type Integer

      def resolve
        result = ::Invoices::RetryBatchService.new(organization: current_organization).call_async

        result.success? ? result.invoices.count : result_error(result)
      end
    end
  end
end
