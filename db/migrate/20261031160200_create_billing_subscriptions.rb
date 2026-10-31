class CreateBillingSubscriptions < ActiveRecord::Migration[8.1]
  def change
    # Every subscription the provider has told us about for an account, with its state as of the latest event time
    # (event_at), so a late or retried webhook never turns the state back. Deleting the account cancels each one that
    # still renews.
    create_table :billing_subscriptions do |t|
      t.string :provider, null: false
      t.string :subscription_id, null: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :plan, null: false
      t.string :status, null: false
      t.boolean :cancel_at_period_end, null: false, default: false
      t.datetime :period_end
      t.datetime :event_at

      t.timestamps
    end
    add_index :billing_subscriptions, %i[provider subscription_id], unique: true
  end
end
