class CreateProviderCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_calls do |t|
      # Kept, without its kit, after the kit is deleted: the daily unit count needs it.
      t.references :kit, foreign_key: { on_delete: :nullify }
      t.string :operation, null: false
      t.string :input_hash, null: false
      t.decimal :units, precision: 8, scale: 2, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.jsonb :response, null: false, default: {}
      t.date :day, null: false, index: true

      t.timestamps
    end
    add_index :provider_calls, [ :operation, :input_hash ], unique: true
  end
end
