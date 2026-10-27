# frozen_string_literal: true

class AddUidToMeetings < ActiveRecord::Migration[8.0]
  class MigrationSeries < ApplicationRecord
    self.table_name = "recurring_meetings"
  end

  def change
    add_column :meetings, :uid, :string
    add_column :recurring_meetings, :uid, :string

    add_index :meetings, :uid, unique: true
    add_index :recurring_meetings, :uid, unique: true

    reversible do |dir|
      dir.up do
        # Backfill Meeting UIDs using current ICal logic
        execute <<~SQL.squish
          UPDATE meetings
          SET uid = meetings.id || '@' || projects.identifier
          FROM projects
          WHERE meetings.project_id = projects.id;
        SQL

        MigrationSeries.select(:id).find_each do |series|
          uid = "#{Setting.app_title}-#{Setting.host_name}-meeting-series-#{series.id}".dasherize
          series.update_columns(uid:)
        end
      end
    end
  end
end
