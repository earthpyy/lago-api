class CreatePreAggregations < ActiveRecord::Migration[7.1]
  def change
    create_table :pre_aggregations, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid, index: true
      t.string :external_subscription_id, null: false
      t.string :code, null: false
      t.timestamp :timestamp, null: false
      t.numeric :aggregated_value, null: false, default: 0.0
      t.jsonb :filters, null: false, default: {}
      t.integer :units, null: false, default: 0
      t.timestamps

      t.index %i[organization_id external_subscription_id code timestamp filters], unique: true
    end
  end
end
