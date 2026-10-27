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

# Who has looked at what, and when last (02 §1.1 注意力, 03 §3.2 "对方还不知道").
# One row per person and object; only the time is kept, never what was read.
class CreateAssistantViews < ActiveRecord::Migration[8.0]
  def change
    create_table :assistant_views do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :subject, polymorphic: true, null: false, index: false
      t.references :project, foreign_key: { on_delete: :cascade }, index: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
    end
    add_index :assistant_views, %i[user_id subject_type subject_id], unique: true, name: "index_assistant_views_once"
    add_index :assistant_views, %i[subject_type subject_id last_seen_at]
  end
end
