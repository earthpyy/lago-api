# frozen_string_literal: true

class AddLogsToInvoice < ActiveRecord::Migration[7.1]
  def change
    add_column :invoices, :logs, :jsonb
  end
end
