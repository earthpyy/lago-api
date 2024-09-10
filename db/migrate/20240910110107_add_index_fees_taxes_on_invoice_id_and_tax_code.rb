class AddIndexFeesTaxesOnInvoiceIdAndTaxCode < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :fees_taxes,
              %i[fee_id tax_code],
              unique: true,
              where: "created_at >= '2023-09-12'",
              algorithm: :concurrently
  end
end
