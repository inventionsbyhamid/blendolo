class CreateCreditEntries < ActiveRecord::Migration[8.1]
  def change
    # The credits ledger: one row per change, with the balance after it. Rows are only ever added.
    create_table :credit_entries do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.integer :delta, null: false
      t.integer :reason, null: false
      # What the change is for: a render, a billing event, a user. Grants and refunds are idempotent on it.
      t.string :source
      t.integer :balance_after, null: false

      t.timestamps
    end
    add_index :credit_entries, [ :user_id, :id ]
    # Render (3) and transfer (4) debits repeat for a render asked for again; every other reason happens once per
    # source.
    add_index :credit_entries, [ :reason, :source ], unique: true, where: "source IS NOT NULL AND reason NOT IN (3, 4)",
      name: "index_credit_entries_once_per_source"
    add_check_constraint :credit_entries, "balance_after >= 0", name: "credit_entries_balance_not_negative"
    add_check_constraint :credit_entries, "delta <> 0", name: "credit_entries_delta_not_zero"
  end
end
