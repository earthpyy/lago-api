class DropIndexFeesTaxesOnFeeIdAndTaxId < ActiveRecord::Migration[7.1]
  def up
    remove_index :fees_taxes, [:fee_id, :tax_id], unique: true
  end

  def down
    add_index :fees_taxes,
              %i[fee_id tax_id],
              unique: true,
              where: "created_at >= '2023-09-12'"
  end
end
