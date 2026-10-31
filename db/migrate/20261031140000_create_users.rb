class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    # People who sign in (Google only for now): who they are at the provider, and how to greet them. No passwords.
    create_table :users do |t|
      t.string :provider, null: false
      t.string :uid, null: false
      t.string :email, null: false
      t.string :name
      t.string :avatar_url
      # A clinic plan is active until this time (set by billing); nil for everyone else.
      t.datetime :clinic_until

      t.timestamps
    end
    add_index :users, [ :provider, :uid ], unique: true
  end
end
