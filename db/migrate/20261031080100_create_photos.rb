class CreatePhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :photos do |t|
      t.references :kit, null: false, foreign_key: true
      t.integer :kind, null: false, default: 0
      t.string :source, null: false
      t.string :sha256
      t.integer :width
      t.integer :height
      t.jsonb :sampled, null: false, default: {}

      t.timestamps
    end
  end
end
