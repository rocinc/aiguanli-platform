# frozen_string_literal: true

class AddParticipationStatusForMeetingParticipant < ActiveRecord::Migration[8.0]
  def change
    add_column :meeting_participants, :participation_status, :string, null: true
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE meeting_participants
          SET participation_status = 'unknown'
          WHERE participation_status IS NULL
        SQL
      end
    end
    change_column_default :meeting_participants, :participation_status, from: nil, to: "needs-action"
    change_column_null :meeting_participants, :participation_status, false
  end
end
