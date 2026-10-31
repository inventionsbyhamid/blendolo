class CreateKits < ActiveRecord::Migration[8.1]
  def change
    create_table :kits do |t|
      t.string :token, null: false, index: { unique: true }
      t.integer :path, null: false, default: 0

      # The five "Your hands" answers, 0..2 each; nil until answered.
      t.integer :tremor
      t.integer :pinch
      t.integer :one_hand
      t.integer :fatigue
      t.integer :near_vision
      t.integer :hands_today, null: false, default: 1

      t.integer :retention_days, null: false, default: 30
      t.datetime :consented_at
      t.datetime :last_active_at, null: false
      t.datetime :purge_after, null: false, index: true

      t.string :chosen_look_key
      t.jsonb :routine, null: false, default: []
      t.string :example_key

      t.timestamps
    end
  end
end
