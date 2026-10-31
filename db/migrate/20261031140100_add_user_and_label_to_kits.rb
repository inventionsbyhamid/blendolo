class AddUserAndLabelToKits < ActiveRecord::Migration[8.1]
  def change
    # A kit may belong to an account; guest kits (and example kits) have none. Deleting an account deletes its kits
    # first, so the key never dangles.
    add_reference :kits, :user, foreign_key: true
    # A short name for the kit, for accounts with several (a clinic's clients).
    add_column :kits, :label, :string, limit: 40
  end
end
