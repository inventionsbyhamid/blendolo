class AddStatusAndOccurredAtToBillingEvents < ActiveRecord::Migration[8.1]
  def change
    # status: applied, ignored (an event we don't act on), or unmatched (no checkout of ours, another customer, a
    # product that isn't ours): unmatched ones need a look from the owner (bin/rails billing:unmatched).
    # occurred_at: when the provider says it happened, which orders events better than when they arrived.
    add_column :billing_events, :status, :integer, null: false, default: 0
    add_column :billing_events, :occurred_at, :datetime
    add_column :billing_events, :reference, :string
    add_index :billing_events, :status
  end
end
