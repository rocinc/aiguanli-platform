# frozen_string_literal: true

class AvoidGlobalRoleOnPlaceholderUser < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      DELETE FROM members
      USING users
      WHERE members.user_id = users.id
        AND members.project_id IS NULL
        AND users.type = 'PlaceholderUser'
    SQL
  end

  def down
    # Nothing to do
  end
end
