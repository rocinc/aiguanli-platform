# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  class Idea < ApplicationRecord
    STATES = %w[open adopted set_aside merged].freeze

    belongs_to :project
    belongs_to :work_package, optional: true
    belongs_to :merged_into, class_name: "Assistant::Idea", optional: true
    has_many :mentions, -> { order(:said_at) }, class_name: "Assistant::IdeaMention", dependent: :delete_all

    scope :open, -> { where(state: "open") }

    def speakers = User.where(id: mentions.select(:speaker_id)).distinct

    def first_mention = mentions.first

    def set_aside!(reason = nil)
      update!(state: "set_aside", set_aside_reason: reason.to_s.squish.truncate(200).presence)
    end

    def reopen!
      update!(state: "open", set_aside_reason: nil)
    end

    def merge_into!(target)
      transaction do
        IdeaMention.where(idea_id: id).update_all(idea_id: target.id)
        update!(state: "merged", merged_into: target)
      end
    end
  end
end
