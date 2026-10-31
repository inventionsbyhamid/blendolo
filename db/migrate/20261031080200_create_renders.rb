class CreateRenders < ActiveRecord::Migration[8.1]
  def change
    create_table :renders do |t|
      t.references :kit, null: false, foreign_key: true
      t.references :photo, null: false, foreign_key: true
      t.references :reference_photo, foreign_key: { to_table: :photos }
      t.integer :kind, null: false, default: 0
      t.string :look_key
      t.jsonb :effects, null: false, default: []
      t.integer :status, null: false, default: 0
      t.string :failure_reason
      t.string :external_id, index: true
      t.datetime :started_at

      t.timestamps
    end
  end
end
