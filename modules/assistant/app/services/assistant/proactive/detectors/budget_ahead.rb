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

module Assistant
  module Proactive
    module Detectors
      # A budget spent faster than its work gets done (03 §3.1, 04 C2): the
      # share spent is ahead of the share of its work packages finished by
      # the configured points. Told to the budget's owner with the forecast at
      # the current pace and what drives the spending (which work, who).
      class BudgetAhead < Base
        AHEAD_POINTS = 10

        def candidates
          return [] unless defined?(::Budget)

          ::Budget.where(project:).includes(:work_packages).filter_map do |budget|
            planned = budget.budget.to_f
            next unless planned.positive?

            wps = budget.work_packages.to_a
            next if wps.empty?

            spent = spent_on(budget)
            spent_percent = (spent * 100 / planned).round
            done_percent = (wps.count { !Assistant::Facts.open?(it) } * 100.0 / wps.size).round
            ahead = spent_percent - done_percent
            next if ahead < AHEAD_POINTS || done_percent >= 100

            owner = budget.author if budget.author.is_a?(User) && budget.author.active?
            owner ||= leads.first
            next unless owner

            build(budget, owner, planned:, spent:, spent_percent:, done_percent:, ahead:, wps:)
          end
        end

        private

        def spent_on(budget)
          entries = TimeEntry.where(entity_type: "WorkPackage", entity_id: budget.work_packages.select(:id))
          labor = entries.sum("COALESCE(overridden_costs, costs)").to_f
          material = if defined?(::CostEntry)
                       CostEntry.where(entity_type: "WorkPackage",
                                       entity_id: budget.work_packages.select(:id))
                                                                           .sum("COALESCE(overridden_costs, costs)").to_f
                     else
                       0
                     end
          (labor + material).round(2)
        end

        def build(budget, owner, planned:, spent:, spent_percent:, done_percent:, ahead:, wps:)
          forecast = done_percent.positive? ? (spent * 100 / done_percent).round(2) : nil
          candidate(
            fingerprint: "#{budget.id}:#{ahead / 10}", recipient: owner, subject: project, nature: :team,
            headline: t("headline", budget: budget.subject, spent: spent_percent, done: done_percent),
            because: [t("spent", spent:, planned:, percent: spent_percent),
                      t("done", done: done_percent, count: wps.size),
                      (t("forecast", forecast:, over: (forecast - planned).round(2)) if forecast && forecast > planned),
                      *drivers(budget)].compact,
            impact: { money: [ahead / 10, 5].min, people: 1 },
            facts: { budget_id: budget.id, planned:, spent:, spent_percent:, done_percent:, ahead_points: ahead, forecast: }
          )
        end

        def drivers(budget)
          entries = TimeEntry.where(entity_type: "WorkPackage", entity_id: budget.work_packages.select(:id))
          by_wp = entries.group(:entity_id).sum("COALESCE(overridden_costs, costs)").sort_by { -it.last }.first(2)
          by_user = entries.group(:user_id).sum(:hours).sort_by { -it.last }.first(2)
          lines = by_wp.filter_map do |id, amount|
            WorkPackage.find_by(id:)&.then do
              t("driver_work", ref: "##{it.id} #{it.subject.truncate(30)}", amount: amount.to_f.round(2))
            end
          end
          names = by_user.filter_map { |id, hours| User.find_by(id:)&.then { "#{it.name} #{hours.to_f.round(1)} h" } }
          lines << t("driver_people", list: names.join(t("separator"))) if names.any?
          lines
        end
      end
    end
  end
end
