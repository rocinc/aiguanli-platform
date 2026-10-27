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
  module Proactive
    module Detectors
      # The last working day of the week, from mid-afternoon (04 C1 时间锚点):
      # each person's week drafted from what they said and what they worked
      # on, waiting for them alone to confirm. Where the team handed the
      # timesheet duty over, the duty does this and the rule stays quiet.
      class WeeklyTimesheet < Base
        FROM_HOUR = 15

        def candidates
          return [] unless last_working_day? && Time.current.hour >= FROM_HOUR
          return [] if Assistant::Duty.active.exists?(project:, kind: "timesheet_draft")

          week = today.beginning_of_week..today
          Routing.people(project).filter_map do |person|
            steps, unlogged, because = Assistant::Duties::TimesheetDraft.week_for(project, person, week)
            next if steps.empty? && unlogged.empty?

            candidate(
              fingerprint: "#{person.id}:#{today.cwyear}-#{today.cweek}", recipient: person, subject: project, nature: :own,
              channel: "brief", headline: I18n.t("assistant.duties.timesheet_draft.headline", count: steps.size + unlogged.size),
              because:, impact: {}, facts: { drafts: steps.size, unlogged: unlogged.size },
              steps_for: ->(_user) { steps.any? ? [option(t("log", count: steps.size), t("log_consequence"), "timesheet_draft", steps)] : [] }
            )
          end
        end

        private

        def last_working_day?
          last = today.end_of_week(:monday)
          last -= 1 until Assistant::Facts.working_day?(last) || last < today
          today == last
        end
      end
    end
  end
end
