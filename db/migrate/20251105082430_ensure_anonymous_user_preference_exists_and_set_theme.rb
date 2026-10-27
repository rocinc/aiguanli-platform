# frozen_string_literal: true

class EnsureAnonymousUserPreferenceExistsAndSetTheme < ActiveRecord::Migration[8.0]
  def up
    say "Ensure anonymous user has preferences and set theme to sync_with_os"

    execute <<~SQL.squish
      INSERT INTO user_preferences (user_id, settings, created_at, updated_at)
      SELECT id, '{"theme": "sync_with_os"}'::jsonb, NOW(), NOW()
      FROM users
      WHERE type = 'AnonymousUser'
      ON CONFLICT (user_id)
      DO UPDATE SET
        settings = user_preferences.settings || '{"theme": "sync_with_os"}'::jsonb,
        updated_at = NOW();
    SQL
  end

  def down
    say "Rollback: reset anonymous user theme to light"

    execute <<~SQL.squish
      UPDATE user_preferences
      SET settings = settings || '{"theme": "light"}'::jsonb,
          updated_at = NOW()
      WHERE user_id IN (SELECT id FROM users WHERE type = 'AnonymousUser');
    SQL
  end
end
