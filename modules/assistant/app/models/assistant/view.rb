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

module Assistant
  # That a person had an object in front of them, and when last. Written
  # when a page stays visible for a moment, read by the value gate to tell
  # whether someone already knows (03 §3.2).
  class View < ApplicationRecord
    self.table_name = "assistant_views"

    belongs_to :user
    belongs_to :subject, polymorphic: true
    belongs_to :project, optional: true

    def self.seen!(user, subject, at: Time.current)
      return unless user&.logged? && subject.is_a?(ActiveRecord::Base) && subject.persisted?

      upsert({ user_id: user.id, subject_type: subject.class.base_class.name, subject_id: subject.id,
               project_id: subject.try(:project_id) || (subject.id if subject.is_a?(Project)),
               first_seen_at: at, last_seen_at: at },
             unique_by: :index_assistant_views_once, update_only: %i[last_seen_at])
    end

    def self.seen_since?(user, subject, since)
      where(user:, subject:).where(last_seen_at: since..).exists?
    end
  end
end
