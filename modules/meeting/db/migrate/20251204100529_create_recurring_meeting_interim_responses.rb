# frozen_string_literal: true

class CreateRecurringMeetingInterimResponses < ActiveRecord::Migration[8.0]
  def change
    create_table :recurring_meeting_interim_responses do |t|
      t.references :recurring_meeting, foreign_key: true, index: false
      t.references :user, foreign_key: true, index: false
      t.datetime :start_time
      t.string :participation_status
      t.text :comment

      t.timestamps

      t.index %i[recurring_meeting_id start_time user_id],
              unique: true
    end
  end
end
