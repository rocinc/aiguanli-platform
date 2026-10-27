# frozen_string_literal: true

class AddEntityToCostEntry < ActiveRecord::Migration[8.0]
  def up
    add_reference :cost_entries, :entity, polymorphic: true
    change_column_null :cost_entries, :work_package_id, true

    execute <<~SQL.squish
      UPDATE cost_entries
      SET
        entity_type = 'WorkPackage',
        entity_id = work_package_id
      WHERE
        work_package_id IS NOT NULL;
    SQL
  end
end
