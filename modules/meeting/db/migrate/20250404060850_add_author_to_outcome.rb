# frozen_string_literal: true

class AddAuthorToOutcome < ActiveRecord::Migration[8.0]
  def change
    add_reference :meeting_outcomes,
                  :author,
                  type: :bigint,
                  foreign_key: { to_table: :users },
                  null: true,
                  index: true
  end
end
