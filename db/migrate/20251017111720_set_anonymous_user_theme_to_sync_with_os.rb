# frozen_string_literal: true

class SetAnonymousUserThemeToSyncWithOs < ActiveRecord::Migration[8.0]
  def up
    say "Set anonymous user theme to sync_with_os"
    execute <<~SQL.squish
      UPDATE user_preferences
      SET settings = settings || '{"theme": "sync_with_os"}'::jsonb
      WHERE user_id = (
        SELECT id FROM users WHERE type = 'AnonymousUser' LIMIT 1
      );
    SQL
  end

  def down
    say "Rollback: Reset anonymous user theme to light"
    execute <<~SQL.squish
      UPDATE user_preferences
      SET settings = settings || '{"theme": "light"}'::jsonb
      WHERE user_id = (
        SELECT id FROM users WHERE type = 'AnonymousUser' LIMIT 1
      );
    SQL
  end
end
