class AddBillingCustomerIdToUsers < ActiveRecord::Migration[8.1]
  def change
    # The account's own customer at the payment provider, made by our server the first time the account buys (never
    # taken from a webhook). Checkout attaches to it, and "Manage" opens only its portal.
    add_column :users, :billing_customer_id, :string
    add_index :users, :billing_customer_id, unique: true, where: "billing_customer_id IS NOT NULL"
  end
end
