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
      # An hour before a meeting (03 §3.1, 04 D1 时间锚点): its host gets the
      # agenda's first draft — what the last meeting of the series said and
      # where each thing stands, then what is due, late or waiting for an
      # answer among the people invited — as agenda items to add with one
      # click. Only what the agenda does not already cover.
      class MeetingPrep < Base
        MINUTES_BEFORE = 70
        MINUTES_BEFORE_MIN = 0

        def candidates
          from = Time.current + MINUTES_BEFORE_MIN.minutes
          to = Time.current + MINUTES_BEFORE.minutes
          ::Meeting.where(project:, template: false).where.not(state: %i[cancelled closed in_progress])
                   .where(start_time: from..to).includes(:author, :agenda_items, participants: :user).filter_map do |meeting|
            host = meeting.author
            next unless host.is_a?(User) && host.active?

            sections = OpenProject::LocaleHelper.with_locale_for(host) { draft(meeting) }
            next if sections.values.all?(&:empty?)

            build(meeting, host, sections)
          end
        end

        private

        def draft(meeting)
          Assistant::MeetingRecap.new(meeting, meeting.author, today:, shared: true).sections
                                 .transform_values { |entries| entries.map { { line: it.line } } }
        end

        def build(meeting, host, sections)
          lines = sections.values.flatten.map { it[:line] }
          candidate(
            fingerprint: meeting.id.to_s, recipient: host, subject: meeting, nature: :team, channel: "notification",
            headline: t("headline", meeting: meeting.title.truncate(40), time: I18n.l(meeting.start_time.in_time_zone(host.time_zone), format: :time)),
            because: lines.first(5), impact: { deadline: true, people: meeting.participants.size },
            facts: sections.transform_values(&:size),
            steps_for: ->(user) { [agenda_option(meeting, sections, user)] }
          )
        end

        def agenda_option(meeting, sections, user)
          steps = OpenProject::LocaleHelper.with_locale_for(user) do
            sections.filter_map do |key, entries|
              next if entries.empty?

              agenda_step(meeting, t("sections.#{key}"), entries.map { "- #{it[:line]}" }.join("\n"), minutes: 5)
            end
          end
          option(t("add", count: steps.size), t("add_consequence"), "meeting_prep", steps)
        end
      end
    end
  end
end
