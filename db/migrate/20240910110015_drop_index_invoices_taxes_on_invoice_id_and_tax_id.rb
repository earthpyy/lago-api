class DropIndexInvoicesTaxesOnInvoiceIdAndTaxId < ActiveRecord::Migration[7.1]
  def up
    remove_index :invoices_taxes, [:invoice_id, :tax_id], unique: true
  end

  def down

    add_index :invoices_taxes,
              %i[invoice_id tax_id],
              unique: true,
              where: "created_at >= '2023-09-12'"
  end
end
