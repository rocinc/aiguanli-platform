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
      # A work package on a version's critical chain is late or about to be,
      # and the version date would slip. Told to whoever leads the version,
      # with a re-plan: move the version, or hand the next link to someone
      # with room so the date holds.
      class CriticalSlip < Base
        HORIZON_DAYS = 60

        def candidates
          versions.flat_map do |version|
            readiness = Assistant::Facts::VersionReadiness.new(version, today:)
            chain = graph.critical_chain(version)
            next [] if chain.empty?

            at_risk = chain.select { (graph.slack(it.id) || 1) <= 0 || (it.due_date && it.due_date < today) }
            next [] if at_risk.empty? && readiness.slip_days.zero?

            weakest = at_risk.min_by { graph.slack(it.id) || 0 } || chain.last
            wp = WorkPackage.find(weakest.id)
            leads.map { |lead| build(version, readiness, chain, wp, lead) }
          end
        end

        private

        def versions
          project.shared_versions.where(status: "open").where.not(effective_date: nil)
                 .where(effective_date: today..(today + HORIZON_DAYS))
        end

        def build(version, readiness, chain, wp, lead)
          slip = readiness.slip_days
          reschedules = Assistant::Facts::History.new(wp).reschedules.size
          candidate(
            fingerprint: "#{version.id}:#{wp.id}:#{wp.due_date}:#{slip}", recipient: lead, subject: wp, nature: :team,
            headline: t("headline", ref: "##{wp.id}", version: version.name, slip:, times: reschedules),
            because: [t("chain", chain: chain.map do
              "##{it.id}"
            end.join(" → "), version: version.name, date: day(version.effective_date)),
                      readiness.because,
                      (t("reschedules", count: reschedules) if reschedules.positive?)].compact,
            impact: { critical_path: true, external: version.sharing != "none", cascade: chain.size, people: chain.filter_map(&:assignee_id).uniq.size },
            act_by: version.effective_date, effort_days: 1,
            facts: { version: version.name, slip_working_days: slip, since: wp.updated_at },
            steps_for: ->(_user) { options(version, chain, wp, slip) }
          )
        end

        def options(version, chain, wp, slip)
          list = []
          if slip.positive?
            new_date = Assistant::Facts.add_working_days(version.effective_date, slip)
            list << option(t("move_version", version: version.name, date: day(new_date)), t("move_version_consequence"),
                           "move_version", [{ "op" => "update_version", "type" => "Version", "id" => version.id,
                                              "attributes" => { "effective_date" => new_date.iso8601 } }])
          end
          after = chain.drop_while { it.id != wp.id }.drop(1).first
          if after && (successor = WorkPackage.find_by(id: after.id))
            hours = Assistant::Facts.remaining_hours(successor).nonzero? || 8.0
            helper, free = free_member(today, successor.due_date || version.effective_date, hours,
                                       except: [successor.assigned_to_id, wp.assigned_to_id].compact)
            if helper
              list << option(t("parallel", ref: "##{successor.id}", name: helper.name),
                             t("parallel_consequence", name: helper.name, free:), "reassign",
                             [step(successor, { "assigned_to_id" => helper.id })])
            end
          end
          list
        end
      end
    end
  end
end
