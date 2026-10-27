# frozen_string_literal: true

class RemoveTimesForMeetingAgendaItems < ActiveRecord::Migration[8.0]
  def change
    remove_column :meeting_agenda_items, :start_time, :timestamp
    remove_column :meeting_agenda_items, :end_time, :timestamp

    remove_column :meeting_agenda_item_journals, :start_time, :timestamp
    remove_column :meeting_agenda_item_journals, :end_time, :timestamp
  end
end
