class CreateShares < ActiveRecord::Migration[8.1]
  def change
    create_table :shares do |t|
      t.references :kit, null: false, foreign_key: true
      t.string :token, null: false, index: { unique: true }
      t.integer :audience, null: false, default: 0
      t.integer :scope, null: false, default: 0
      t.datetime :expires_at, null: false
      t.datetime :revoked_at

      t.timestamps
    end
  end
end
