# frozen_string_literal: true

class AddIndicesToMeetingParticipants < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :meeting_participants, :meeting_id, algorithm: :concurrently
    add_index :meeting_participants, :user_id, algorithm: :concurrently
  end
end
