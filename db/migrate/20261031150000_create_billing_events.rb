class CreateBillingEvents < ActiveRecord::Migration[8.1]
  def change
    # Every verified payment provider webhook, stored once by (provider, event_id) and applied in the same
    # transaction. kind is ours (BillingEvent.kinds), event_type the provider's own name. credits: what this event
    # added (nil when it added none). note: why an event changed nothing. A deleted account keeps its payment records
    # without the link to it (they hold ids and amounts, never names or emails).
    create_table :billing_events do |t|
      t.string :provider, null: false
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.integer :kind
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :plan
      t.string :customer_id
      t.string :subscription_id
      t.string :payment_id
      t.integer :amount_cents
      t.string :currency
      t.datetime :period_end
      t.integer :credits
      t.string :note
      t.jsonb :payload, null: false, default: {}

      t.timestamps
    end
    add_index :billing_events, %i[provider event_id], unique: true
    add_index :billing_events, %i[provider subscription_id]
    add_index :billing_events, %i[provider payment_id]
  end
end
