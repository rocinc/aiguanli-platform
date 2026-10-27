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
  module Actions
    module Steps
      # Writes a decision or a piece of information as an outcome of a
      # meeting agenda item, the way the meeting itself records them.
      class CreateMeetingOutcome < Base
        def project = MeetingAgendaItem.find_by(id: attributes["agenda_item_id"])&.meeting&.project

        def call(user:, cause:)
          item = MeetingAgendaItem.find_by(id: attributes["agenda_item_id"])
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless item
          return Outcome.failure(I18n.t("assistant.actions.errors.meeting_not_running")) unless item.meeting&.in_progress?

          call = ::MeetingOutcomes::CreateService.new(user:).call(
            meeting_agenda_item: item, kind: attributes["kind"].presence || "decision", notes: attributes["notes"],
            work_package_id: attributes["work_package_id"]
          )
          created_outcome(call)
        end
      end
    end
  end
end
