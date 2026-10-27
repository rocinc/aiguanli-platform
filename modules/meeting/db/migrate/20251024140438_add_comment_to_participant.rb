# frozen_string_literal: true

class AddCommentToParticipant < ActiveRecord::Migration[8.0]
  def change
    add_column :meeting_participants, :comment, :text, null: true
  end
end
