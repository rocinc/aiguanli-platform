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
      # What repeats across sprints (03 §6.4): defects found mostly in the last
      # two days, or much of every sprint carried over, sprint after sprint;
      # and a retrospective that said to use a step — "测试提前" — whose
      # status nobody entered since. Said once per sprint to whoever leads, on
      # the next retrospective's agenda when there is one.
      class CrossSprintPattern < Base
        RETRO = /回顾|复盘|retro/i
        MIN_SPRINTS = 3
        CARRYOVER_PERCENT = 30

        def candidates
          rows = Assistant::Facts::SprintHistory.new(project, today:).rows
          return [] if rows.size < MIN_SPRINTS

          found = findings(rows)
          return [] if found.empty?

          meeting = next_meeting(where: ->(m) { m.title.match?(RETRO) })
          leads.map { build(rows.last.sprint, found, meeting, it) }
        end

        # [[kind, headline, lines]]
        def findings(rows = Assistant::Facts::SprintHistory.new(project, today:).rows)
          return [] if rows.size < MIN_SPRINTS

          [late_defects(rows), carryover(rows), *unused_steps].compact
        end

        private

        def late_defects(rows)
          hits = rows.select { it.late_share && it.defects.size >= 2 && it.late_share >= 0.5 }
          return if hits.size < MIN_SPRINTS

          [:late_defects, t("late_defects", count: hits.size, total: rows.size),
           hits.map { t("late_line", sprint: it.sprint.name, late: it.late_defects.size, all: it.defects.size) }]
        end

        def carryover(rows)
          hits = rows.select { it.planned >= 3 && it.carryover_share >= CARRYOVER_PERCENT.fdiv(100) }
          return if hits.size < MIN_SPRINTS

          [:carryover, t("carryover", count: hits.size, total: rows.size),
           hits.map { t("carryover_line", sprint: it.sprint.name, open: it.unfinished.size, all: it.planned) }]
        end

        # A status a retrospective named, never entered since it was said.
        def unused_steps
          retro_items.filter_map do |item|
            status = Status.where(is_closed: false).detect { item.title.include?(it.name) || item.quote.include?(it.name) } or next
            used = Journal::WorkPackageJournal.where(status_id: status.id).joins(:journal)
                                              .where(journals: { journable_type: "WorkPackage", created_at: item.stated_at.. })
                                              .where(project_id: project.id).exists?
            next if used

            [:"unused_#{item.id}", t("unused", status: status.name, meeting: item.subject.title.truncate(30)),
             [t("said", on: day(item.stated_at.to_date), quote: item.quote.truncate(80))]]
          end
        end

        def retro_items
          meetings = ::Meeting.where(project:, template: false).where(start_time: 120.days.ago..).select { it.title.match?(RETRO) }
          Assistant::Intent.where(project:, subject: meetings).where.not(status: "dismissed").includes(:subject).to_a
        end

        # One brief entry for all of them: they are read together, at the retrospective.
        def build(sprint, found, meeting, lead)
          headline = found.first[1]
          headline = t("and_more", headline:, count: found.size - 1) if found.size > 1
          lines = found.flat_map { [it[1], *it[2].first(3)] }
          candidate(
            fingerprint: "#{sprint.id}:#{found.map(&:first).join(',')}", recipient: lead, subject: sprint, nature: :team,
            channel: "brief", headline:, because: lines.first(8), impact: { people: 2 },
            facts: { patterns: found.map { it.first.to_s }, sprint_id: sprint.id },
            steps_for: meeting && ->(user) { [agenda_option(meeting, found, user)] }
          )
        end

        def agenda_option(meeting, found, _user)
          notes = found.map { |_, headline, lines| ["**#{headline}**", *lines.map { "- #{it}" }].join("\n") }.join("\n\n")
          option(t("agenda", meeting: meeting.title.truncate(30)), t("agenda_consequence"), "pattern_agenda",
                 [agenda_step(meeting, t("agenda_title"), notes, minutes: 10)])
        end
      end
    end
  end
end
