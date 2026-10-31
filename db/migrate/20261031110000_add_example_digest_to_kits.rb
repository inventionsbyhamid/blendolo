class AddExampleDigestToKits < ActiveRecord::Migration[8.1]
  def change
    # Example kits remember which version of their example (yml entry and files) they were built from.
    add_column :kits, :example_digest, :string
  end
end
