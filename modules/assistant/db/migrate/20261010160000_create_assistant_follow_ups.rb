# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

# Where a piece of work was asked for (a forum topic, a news comment), so
# the assistant can go back and say what became of it (06 S3, 04 D2 到来).
class CreateAssistantFollowUps < ActiveRecord::Migration[8.0]
  def change
    create_table :assistant_follow_ups do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :place, polymorphic: true, null: false
      t.references :work_package, null: false, foreign_key: { on_delete: :cascade }
      t.references :asker, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :state, null: false, default: "waiting"
      t.jsonb :told, null: false, default: []
      t.timestamps
    end
    add_index :assistant_follow_ups, %i[place_type place_id work_package_id], unique: true,
                                                                               name: "index_assistant_follow_ups_once"
  end
end
