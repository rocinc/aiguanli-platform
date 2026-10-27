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
      # Someone booked time off that overlaps work they hold (04 C1: "请假一旦
      # 写入，立刻重算受影响的排期"). Whoever leads the project, and whoever is
      # accountable for the work it hits, hears which work that is, how much of
      # it is on a critical chain, and who has room to take it over or how far
      # it moves.
      class AbsenceRipple < Base
        def candidates
          UserNonWorkingTime.where(user_id: Routing.people(project).map(&:id)).where(created_at: since..)
                            .where("end_date >= ?", today).flat_map { ripple(it) }
        end

        private

        def ripple(absence)
          person = absence.user
          hit = open_work_packages.select do |wp|
            wp.assigned_to_id == person.id && wp.due_date && (wp.start_date || wp.due_date) <= absence.end_date &&
              wp.due_date >= absence.start_date
          end
          return [] if hit.empty?

          critical = hit.select { graph.slack(it.id)&.<=(Assistant::Facts.working_days_between(absence.start_date, absence.end_date)) }
          recipients = (leads + hit.map(&:responsible)).uniq.select { it.is_a?(User) && it.active? && it != person }
          recipients.map do |lead|
            candidate(
              fingerprint: "#{absence.id}", recipient: lead, subject: hit.first, nature: :team,
              headline: t("headline", name: person.name, from: day(absence.start_date), to: day(absence.end_date), count: hit.size),
              because: [t("absence", name: person.name, from: day(absence.start_date), to: day(absence.end_date)),
                        t("hit", list: hit.first(6).map { "##{it.id}" }.join("、")),
                        (t("critical", list: critical.map { "##{it.id}" }.join("、")) if critical.any?)].compact,
              facts: { basis_links: [absence_source(absence)] },
              impact: { critical_path: critical.any?, cascade: hit.size, people: 2 },
              act_by: absence.start_date, effort_days: 1,
              steps_for: ->(_user) { options(hit, absence, person) }
            )
          end
        end

        def absence_source(absence)
          Assistant::Action.where(status: "executed", on_behalf_of_id: absence.user_id).order(:id).reverse_each.lazy.filter_map do |action|
            steps = Array(action.plan.try(:dig, "steps") || action.plan)
            next unless steps.any? { it.is_a?(Hash) && it["op"] == "create_non_working_time" && it.dig("attributes", "start_date") == absence.start_date.iso8601 }

            Array(action.basis).first.try(:[], "gid")
          end.first
        end

        def options(hit, absence, person)
          hit.first(3).filter_map do |wp|
            hours = Assistant::Facts.remaining_hours(wp).nonzero? || 8.0
            helper, free = free_member(absence.start_date, wp.due_date, hours, except: [person.id])
            next unless helper

            option(t("hand_over", ref: "##{wp.id}", name: helper.name), t("hand_over_consequence", name: helper.name, free:),
                   "reassign", [step(wp, { "assigned_to_id" => helper.id })])
          end.presence || hit.first(2).map do |wp|
            days = Assistant::Facts.working_days_between([absence.start_date, wp.start_date || absence.start_date].max,
                                                         absence.end_date)
            option(t("push", ref: "##{wp.id}", days:), t("push_consequence"), "reschedule", [step(wp, shift(wp, days))])
          end
        end
      end
    end
  end
end
