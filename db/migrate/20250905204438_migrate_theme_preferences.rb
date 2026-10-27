# frozen_string_literal: true

class MigrateThemePreferences < ActiveRecord::Migration[8.0]
  def up
    migrate_theme_preferences_to_new_structure
  end

  def down
    migrate_theme_preferences_to_old_structure
  end

  private

  def migrate_theme_preferences_to_new_structure
    say "Migrate light_high_contrast -> light theme with increase_theme_contrast: true"
    execute <<~SQL.squish
      UPDATE user_preferences
      SET settings = settings || '{"theme": "light", "increase_theme_contrast": true}'::jsonb
      WHERE settings ->> 'theme' = 'light_high_contrast';
    SQL

    say "Migrate dark_high_contrast -> dark theme with increase_theme_contrast: true"
    execute <<~SQL.squish
      UPDATE user_preferences
      SET settings = settings || '{"theme": "dark", "increase_theme_contrast": true}'::jsonb
      WHERE settings ->> 'theme' = 'dark_high_contrast';
    SQL
  end

  def migrate_theme_preferences_to_old_structure
    say "Rollback: Convert light theme with high contrast back to light_high_contrast"
    execute <<~SQL.squish
      UPDATE user_preferences
      SET settings = (settings - 'increase_theme_contrast') || '{"theme": "light_high_contrast"}'::jsonb
      WHERE settings ->> 'theme' = 'light'
        AND (settings ->> 'increase_theme_contrast')::boolean = true;
    SQL

    say "Rollback: Convert dark theme with high contrast back to dark_high_contrast"
    execute <<~SQL.squish
      UPDATE user_preferences
      SET settings = (settings - 'increase_theme_contrast') || '{"theme": "dark_high_contrast"}'::jsonb
        WHERE settings ->> 'theme' = 'dark'
          AND (settings ->> 'increase_theme_contrast')::boolean = true;
    SQL
  end
end
