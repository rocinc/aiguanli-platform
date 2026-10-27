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
      # The working day before a sprint's planning meeting (04 A3, 06 S4): the
      # agenda gets what the meeting needs to decide — each person's hours
      # and what was taken off them, what the last sprint left open and why,
      # the scope that fits by priority against the gap, the risks in it,
      # ideas several people raised, and a first sprint goal. Offered to the
      # host as agenda items; the decisions in the meeting go through the
      # usual proposals.
      class SprintPlanningPrep < Base
        PLANNING = /计划|规划|planning/i
        GOAL_ITEM = /目标|goal/i
        DECISION_ITEM = /决定|行动项|decision/i
        LINES = 5
        MINUTES = { goal: 10, capacity: 5, carryover: 10, scope: 20, risks: 10, ideas: 5 }.freeze

        def candidates
          return [] unless defined?(::Sprint)

          sprint = next_sprint or return []
          meeting = planning_meeting(sprint) or return []
          host = meeting.author
          return [] unless host.is_a?(User) && host.active?

          sections = sections_for(sprint, meeting)
          [candidate(
            fingerprint: "#{sprint.id}:#{meeting.id}", recipient: host, subject: meeting, nature: :team, channel: "brief",
            headline: t("headline", sprint: sprint.name, meeting: meeting.title.truncate(30)),
            because: [sections[:capacity].first, sections[:scope].last, *sections[:risks].first(2)].compact,
            impact: { people: sections[:capacity].size - 1, deadline: true }, act_by: meeting.start_time.to_date,
            facts: { sprint_id: sprint.id, meeting_id: meeting.id }.merge(sections.transform_values(&:size)),
            steps_for: ->(user) { [agenda_option(meeting, sections, user)] }
          )]
        end

        private

        def next_sprint
          ::Sprint.where(project:).where(start_date: (today + 1)..).order(:start_date).first
        end

        # The planning meeting before the sprint starts, held tomorrow or on
        # the sprint's first day: today is the working day before it.
        def planning_meeting(sprint)
          eve = Assistant::Facts.next_working_day(today)
          ::Meeting.where(project:, template: false).where.not(state: %i[cancelled closed])
                   .where(start_time: eve.beginning_of_day..[eve, sprint.start_date].max.end_of_day)
                   .order(:start_time).detect { it.title.match?(PLANNING) }
        end

        def sections_for(sprint, meeting)
          previous = ::Sprint.where(project:).where(finish_date: ...sprint.start_date).order(finish_date: :desc).first
          { goal: goal_lines(sprint, meeting), capacity: capacity_lines(sprint), carryover: carryover_lines(previous, sprint),
            scope: scope_lines(sprint), risks: risk_lines(sprint), ideas: idea_lines }
        end

        def planned_work(sprint)
          @planned_work ||= sprint.work_packages.where.not(status_id: Assistant::Facts.closed_status_ids)
                                  .includes(:priority, :assigned_to, :status).to_a
        end

        def planned_versions(sprint) = @planned_versions ||= Assistant::Facts.version_ids_of(planned_work(sprint).map(&:id))

        # The soonest open version the sprint's own work belongs to.
        def focus_version(sprint)
          return @focus_version if defined?(@focus_version)

          @focus_version = ::Version.where(id: planned_versions(sprint).values.uniq, status: "open")
                                    .where(effective_date: today..).order(:effective_date).first
        end

        def sprint_people(sprint)
          recent = ::Sprint.where(project:).where(start_date: ..sprint.start_date).order(start_date: :desc).limit(4)
          ids = WorkPackage.where(sprint_id: recent.select(:id)).distinct.pluck(:assigned_to_id).compact
          people = Routing.people(project)
          people.select { ids.include?(it.id) }.presence || people
        end

        def capacity_lines(sprint)
          people = sprint_people(sprint)
          rows = people.map do |person|
            capacity = Assistant::Facts::Capacity.new(person, sprint.start_date, sprint.finish_date)
            elsewhere = Assistant::Facts::Load.new(person, sprint.start_date, sprint.finish_date, today:).entries
                                              .reject { it.work_package.project_id == project.id }.sum(&:hours_in_range).round(1)
            [person, capacity, elsewhere]
          end
          total = rows.sum { |_, capacity, elsewhere| capacity.hours - elsewhere }.round(1)
          [t("capacity_total", hours: total, count: people.size),
           *rows.map do |person, capacity, elsewhere|
             off = [(t("off_absent", days: capacity.absences.size, range: capacity.absence_ranges.map { span(*it) }.join(t("separator"))) if capacity.absences.any?),
                    (t("off_elsewhere", hours: elsewhere) if elsewhere.positive?)].compact
             t("capacity_line", name: person.name, hours: (capacity.hours - elsewhere).round(1),
                                off: off.any? ? t("off", list: off.join(t("separator"))) : "")
           end]
        end

        def carryover_lines(previous, sprint)
          return [] unless previous

          open = previous.work_packages.where.not(status_id: Assistant::Facts.closed_status_ids).includes(:status, :assigned_to)
                         .sort_by { -Assistant::Facts.remaining_hours(it) }
          lines = open.map do |wp|
            reason, keep = Assistant::Duties::SprintCarryover.reason_for(wp)
            t("carryover_line", ref: "##{wp.id}", subject: wp.subject.truncate(40), owner: wp.assigned_to&.name || t("nobody"),
                                reason:, advice: t(keep ? "advice_keep" : "advice_backlog"))
          end
          [*capped(lines), *overloaded(open, sprint)]
        end

        def overloaded(work_packages, sprint)
          work_packages.filter_map(&:assigned_to).uniq.filter_map do |person|
            capacity = Assistant::Facts::Capacity.new(person, sprint.start_date, sprint.finish_date).hours
            load = Assistant::Facts::Load.new(person, sprint.start_date, sprint.finish_date, today:).hours
            t("carryover_overload", name: person.name, capacity:, load:, gap: (load - capacity).round(1)) if load > capacity
          end
        end

        def capped(lines)
          return lines if lines.size <= LINES

          [*lines.first(LINES), t("more", count: lines.size - LINES)]
        end

        # By priority, the soonest version's work first, from the sprint's own
        # scope then the unscheduled backlog, until the team's room is used:
        # story points against the recent velocity when the team plans in
        # points, hours otherwise.
        def scope_lines(sprint)
          planned = planned_work(sprint)
          backlog = open_work_packages.select { it.sprint_id.nil? && it.children.none? }
          candidates = planned + backlog.reject { planned.include?(it) }
          version_ids = planned_versions(sprint).merge(Assistant::Facts.version_ids_of(candidates.map(&:id)))
          focus = focus_version(sprint)
          rank = ->(wp) { version_ids[wp.id].nil? ? 1 : (version_ids[wp.id] == focus&.id ? 0 : 2) }
          ranked = candidates.sort_by { [rank.(it), planned.include?(it) ? 0 : 1, -it.priority&.position.to_i, it.id] }
          velocity = Assistant::Facts::SprintHistory.new(project, today:).velocity if ranked.any? { it.story_points.to_i.positive? }
          room = velocity || sprint_people(sprint).sum do |person|
            Assistant::Facts::Capacity.new(person, sprint.start_date, sprint.finish_date).hours
          end
          size = ->(wp) { velocity ? wp.story_points.to_i : (Assistant::Facts.remaining_hours(wp).nonzero? || 4.0) }
          unit = t(velocity ? "points" : "hours")
          used = 0.0
          fits = ranked.take_while { (used += size.(it)) <= room }
          planned_size = planned.sum(&size).round(1)
          gap = (room - planned_size).round(1)
          versions = ::Version.where(id: version_ids.values.uniq).index_by(&:id)
          shown = fits.first(LINES)
          [*shown.map { scope_line(it, size.(it), unit, rank.(it) == 2 ? versions[version_ids[it.id]] : nil) },
           *scope_rest(shown, fits.drop(LINES), size, unit),
           *scope_unsized(fits, velocity),
           t("#{velocity ? 'scope_points' : 'scope_hours'}.#{gap.negative? ? 'over' : 'under'}", planned: planned_size,
             room: room.round(1), gap: gap.abs)]
        end

        def scope_line(wp, size, unit, version)
          detail = [version&.name, (t("size", size: number(size), unit:) if size.positive?)].compact
          line = t("scope_line", ref: "##{wp.id}", subject: wp.subject.truncate(40))
          detail.any? ? line + t("scope_detail", detail: detail.join(t("separator"))) : line
        end

        def scope_rest(shown, rest, size, unit)
          return [] if rest.empty?

          [t("scope_rest", shown: shown.size, shown_size: number(shown.sum(&size)), count: rest.size, size: number(rest.sum(&size)), unit:,
                           refs: rest.first(10).map { "##{it.id}" }.join(t("separator")))]
        end

        def scope_unsized(fits, velocity)
          unsized = velocity ? fits.select { it.story_points.to_i.zero? } : []
          unsized.any? ? [t("scope_unsized", count: unsized.size, list: unsized.first(8).map { "##{it.id}" }.join(t("separator")))] : []
        end

        def number(value) = value.to_f == value.to_i ? value.to_i : value.to_f.round(1)

        def risk_lines(sprint)
          wps = planned_work(sprint)
          focus = focus_version(sprint)
          release = focus ? Assistant::Facts::ReleaseRisks.new(Assistant::Facts::VersionReadiness.new(focus, today:), today:, graph:).lines.map(&:last) : []
          elsewhere = focus ? wps.reject { planned_versions(sprint)[it.id] == focus.id } : wps
          unassigned = Assistant::Facts::ReleaseRisks.unassigned_line(elsewhere.reject(&:assigned_to_id),
                                                                       key: focus ? "unassigned_other" : "unassigned", version: focus&.name)
          questions = Assistant::Intent.where(project:, kind: "question", status: "open", subject: wps).limit(3)
          [*release, *Assistant::Facts::ReleaseRisks.blocked_lines(elsewhere), unassigned,
           *questions.map { t("risk_question", title: it.title.truncate(60), ref: "##{it.subject_id}") }].compact
        end

        def idea_lines
          Assistant::Idea.open.where(project:, work_package_id: nil).includes(mentions: %i[speaker source]).filter_map do |idea|
            by_speaker = idea.mentions.group_by(&:speaker_id)
            next if by_speaker.size < 2

            names = by_speaker.values.filter_map { it.first.speaker&.name }
            sources = by_speaker.values.filter_map { idea_source(it.first) }
            t("idea_line", title: idea.title.truncate(50), who: names.join(t("separator")), sources: sources.any? ? t("idea_sources", list: sources.join(t("separator"))) : "")
          end.first(3)
        end

        def idea_source(mention)
          url = Assistant::Provenance.url_for_basis(Assistant::Basis.for(mention.source).to_h) or return
          kind = mention.source.is_a?(::Message) ? "idea_message" : "idea_comment"
          "[#{t(kind, date: short((mention.said_at || mention.created_at).to_date))}](#{url})"
        end

        # The sprint goal as the team wrote it, or the top items' titles as a
        # start; nothing when the host already put a goal on the agenda.
        def goal_lines(sprint, meeting)
          return [] if meeting.agenda_items.any? { it.title.to_s.match?(GOAL_ITEM) }

          written = sprint.try(:goal_text_for, project).presence
          return [t("goal_written", goal: written)] if written

          top = sprint.work_packages.includes(:priority).max_by(3) { it.priority&.position.to_i }
          top.any? ? [t("goal_draft", list: top.map { it.subject.truncate(30) }.join(t("separator")))] : []
        end

        def agenda_option(meeting, sections, user)
          shown = sections.reject { |_, lines| lines.empty? }
          minutes = minutes_for(meeting, shown.keys)
          steps = OpenProject::LocaleHelper.with_locale_for(user) do
            items = shown.map do |key, lines|
              agenda_step(meeting, t("sections.#{key}"), lines.map { "- #{it}" }.join("\n"), minutes: minutes[key])
            end
            items << agenda_step(meeting, t("sections.decisions"), t("decisions_note"), minutes: decision_minutes(meeting)) unless decisions?(meeting)
            items
          end
          option(t("add", count: steps.size), t("add_consequence"), "planning_prep", steps)
        end

        def decisions?(meeting) = meeting.agenda_items.any? { it.title.to_s.match?(DECISION_ITEM) }

        def decision_minutes(meeting) = meeting.duration.to_f >= 1 ? 15 : 10

        # Section lengths scaled down, when needed, so that what is already
        # on the agenda, these sections and the time for decisions fit the meeting.
        def minutes_for(meeting, keys)
          weights = MINUTES.slice(*keys)
          total = (meeting.duration.to_f * 60).round
          return weights if total.zero?

          budget = total - meeting.agenda_items.sum { it.duration_in_minutes.to_i } - decision_minutes(meeting)
          return weights if weights.values.sum <= budget

          scale = [budget, 0].max.fdiv(weights.values.sum)
          weights.transform_values { [(it * scale / 5).floor * 5, 5].max }
        end

        def short(date) = I18n.l(date, format: "%-m/%-d")

        def span(from, to) = from == to ? short(from) : "#{short(from)}–#{short(to)}"
      end
    end
  end
end
