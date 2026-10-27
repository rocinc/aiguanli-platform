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
      # The working day before a retrospective (03 §6.4 兑现的回响): what the
      # last one said to do, whether it was done, and what the numbers did
      # since — carry-over and late defects in the sprint before against the
      # sprints after. Offered to the host as the first item on the agenda.
      class RetroFollowUp < Base
        def candidates
          meeting = upcoming_retro or return []
          previous = previous_retro(meeting) or return []
          items = Assistant::Intent.where(project:, subject: previous, kind: %w[commitment deferral decision])
                                    .where.not(status: "dismissed").includes(:owner).to_a
          return [] if items.empty?

          lines = items.map { line(it) }
          effect = effect_since(previous)
          host = meeting.author
          return [] unless host.is_a?(User) && host.active?

          [candidate(
            fingerprint: meeting.id.to_s, recipient: host, subject: meeting, nature: :team, channel: "brief",
            headline: t("headline", meeting: meeting.title.truncate(30), done: items.count { done?(it) }, count: items.size),
            because: [*lines.first(5), effect].compact, impact: { people: items.filter_map(&:owner_id).uniq.size },
            act_by: meeting.start_time.to_date,
            facts: { previous_id: previous.id, items: items.size },
            steps_for: ->(_user) { [agenda_option(meeting, previous, lines, effect)] }
          )]
        end

        private

        def upcoming_retro
          eve = Assistant::Facts.next_working_day(today)
          next_meeting(by: eve, where: ->(m) { m.title.match?(CrossSprintPattern::RETRO) && m.start_time.to_date > today })
        end

        def previous_retro(meeting)
          ::Meeting.where(project:, template: false).where(start_time: ...meeting.start_time).order(start_time: :desc)
                   .detect { it.title.match?(CrossSprintPattern::RETRO) }
        end

        def done?(item)
          return true if item.status == "done"

          wps = linked_work_packages(item)
          wps.any? && wps.none? { Assistant::Facts.open?(it) }
        end

        def linked_work_packages(item)
          ids = [item.work_package_id].compact
          ids.empty? ? [] : WorkPackage.where(id: ids).to_a
        end

        def line(item)
          state = if done?(item) then t("done")
                  elsif (wps = linked_work_packages(item)).any? then wps.map { "##{it.id} #{it.status.name}" }.join(t("separator"))
                  else t("not_done")
                  end
          t("item", title: item.title.truncate(60), owner: item.owner&.name || t("nobody"), state:)
        end

        # The sprint that ended before the last retrospective, against the ones since.
        def effect_since(previous)
          rows = Assistant::Facts::SprintHistory.new(project, today:).rows
          before, after = rows.partition { it.sprint.finish_date <= previous.start_time.to_date }
          return if before.empty? || after.empty?

          was = before.last
          now = after.sum(&:carryover_share) / after.size
          late_was = was.late_share
          late_now = after.filter_map(&:late_share).then { it.empty? ? nil : it.sum / it.size }
          parts = [t("carryover", was: percent(was.carryover_share), now: percent(now))]
          parts << t("late", was: percent(late_was), now: percent(late_now)) if late_was && late_now
          parts.join(t("separator"))
        end

        def percent(share) = (share * 100).round

        def agenda_option(meeting, previous, lines, effect)
          notes = [t("agenda_intro", meeting: previous.title, date: day(previous.start_time.to_date)), "",
                   *lines.map { "- #{it}" }, ("" if effect), effect].compact.join("\n")
          option(t("agenda"), t("agenda_consequence"), "retro_follow_up",
                 [agenda_step(meeting, t("agenda_title"), notes, minutes: 10)])
        end
      end
    end
  end
end
