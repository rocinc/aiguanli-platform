# frozen_string_literal: true

class RenameCreateMinutesToManageOutcomes < ActiveRecord::Migration[8.0]
  def up
    execute <<-SQL.squish
      UPDATE role_permissions
      SET permission = 'manage_outcomes'
      WHERE permission = 'create_meeting_minutes'
    SQL
  end

  def down
    execute <<-SQL.squish
      UPDATE role_permissions
      SET permission = 'create_meeting_minutes'
      WHERE permission = 'manage_outcomes'
    SQL
  end
end
