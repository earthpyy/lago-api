class AddIndexInvoicesTaxesOnInvoiceIdAndTaxCode < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :invoices_taxes,
              %i[invoice_id tax_code],
              unique: true,
              where: "created_at >= '2023-09-12'",
              algorithm: :concurrently
  end
end
