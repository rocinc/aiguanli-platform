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
  # A standing job the team handed to the assistant, with the person who
  # handed it over and answers for it.
  class Duty < ApplicationRecord
    KINDS = %w[weekly_status sprint_carryover release_watch decision_log advance_merged_pr meeting_followup
               timesheet_draft devils_advocate onboarding].freeze

    belongs_to :project
    belongs_to :delegator, class_name: "User"

    validates :kind, inclusion: { in: KINDS }, uniqueness: { scope: :project_id }

    scope :active, -> { where(active: true) }

    def handler = "Assistant::Duties::#{kind.camelize}".constantize

    def due?(now = Time.current) = handler.due?(self, now)

    def stale? = unseen_runs >= 4
  end
end
