class CreateCheckouts < ActiveRecord::Migration[8.1]
  def change
    # One checkout our server started: the random token goes to the provider in the session's metadata and comes back
    # on its webhooks, so a payment is tied to the account that started it (and only if the paying customer is that
    # account's own customer too). url: the provider's page, so an unfinished Clinic checkout can be picked up again
    # instead of starting a second subscription.
    create_table :checkouts do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :provider, null: false
      t.string :plan, null: false
      t.string :token, null: false, index: { unique: true }
      t.integer :status, null: false, default: 0
      t.string :url

      t.timestamps
    end
    add_index :checkouts, %i[user_id plan status created_at]
  end
end
