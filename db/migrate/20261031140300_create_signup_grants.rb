class CreateSignupGrants < ActiveRecord::Migration[8.1]
  def change
    # The free credits are once per Google account, even after the account is deleted: a one-way HMAC of the
    # provider and its user id, nothing else.
    create_table :signup_grants do |t|
      t.string :account_digest, null: false, index: { unique: true }

      t.timestamps
    end
  end
end
