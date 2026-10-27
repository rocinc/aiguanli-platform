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
      # Logged time that cannot be right (04 C1 异常：例如一天 16 小时): one
      # person's entries in this project on one day add up to more than
      # MAX_DAY_HOURS. Asked privately, once per day logged, with
      # the entries listed so the slip is easy to find; only they can fix it.
      class TimeEntryAnomaly < Base
        MAX_DAY_HOURS = 14

        def candidates
          days = TimeEntry.where(project:, spent_on: (today - 7)..today, ongoing: false)
                          .where(updated_at: since..).distinct.pluck(:user_id, :spent_on)
          days.filter_map do |user_id, spent_on|
            entries = TimeEntry.where(user_id:, spent_on:, ongoing: false).includes(:entity, :project).to_a
            total = entries.sum(&:hours).round(1)
            next if total <= MAX_DAY_HOURS

            person = entries.first.user
            next unless person.is_a?(User) && person.active? && !person.is_a?(AssistantUser)

            build(person, spent_on, entries, total)
          end
        end

        private

        def build(person, spent_on, entries, total)
          candidate(
            fingerprint: "#{person.id}:#{spent_on.iso8601}", recipient: person, subject: project, nature: :own, channel: "brief",
            headline: t("headline", hours: total, date: day(spent_on)),
            because: entries.sort_by { -it.hours }.first(5).map do
              t("entry", hours: it.hours.round(1), what: it.entity.is_a?(WorkPackage) ? "##{it.entity.id}" : it.project.name)
            end,
            impact: {}, facts: { total:, spent_on: },
            steps_for: ->(_user) { [] }
          )
        end
      end
    end
  end
end
