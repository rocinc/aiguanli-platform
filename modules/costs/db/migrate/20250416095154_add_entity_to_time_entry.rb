# frozen_string_literal: true

class AddEntityToTimeEntry < ActiveRecord::Migration[8.0]
  def up
    add_reference :time_entries, :entity, polymorphic: true
    add_reference :time_entry_journals, :entity, polymorphic: true

    execute <<~SQL.squish
      UPDATE time_entries
      SET
        entity_type = 'WorkPackage',
        entity_id = work_package_id
      WHERE
        work_package_id IS NOT NULL;
    SQL

    execute <<~SQL.squish
      UPDATE time_entry_journals
      SET
        entity_type = 'WorkPackage',
        entity_id = work_package_id
      WHERE
        work_package_id IS NOT NULL;
    SQL
  end
end
