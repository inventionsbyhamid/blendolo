class AddInputHashToRenders < ActiveRecord::Migration[8.1]
  def change
    # The provider call cache key (ProviderCall#input_hash): renders with the same inputs share one call.
    add_column :renders, :input_hash, :string
    add_index :renders, :input_hash
  end
end
