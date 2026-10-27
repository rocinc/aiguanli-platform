# frozen_string_literal: true

class AddEntityIndexForCosts < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :time_entries, %i[entity_type entity_id], algorithm: :concurrently
    add_index :time_entry_journals, %i[entity_type entity_id], algorithm: :concurrently
    add_index :cost_entries, %i[entity_type entity_id], algorithm: :concurrently
  end
end
