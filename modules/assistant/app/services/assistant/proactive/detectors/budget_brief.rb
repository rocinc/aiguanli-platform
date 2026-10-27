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
      # On the last working day of a month, and of a quarter (04 C2 时间锚点):
      # what the period cost against what was planned and what got done,
      # where it went, and what the pace says about the rest. Money only for
      # those who may see budgets (07 D7); hours otherwise.
      class BudgetBrief < Base
        def candidates
          return [] unless last_working_day_of_month?

          leads.filter_map do |lead|
            burn = Assistant::Facts::BudgetBurn.new(project, viewer: lead)
            next if burn.spent_hours.zero?

            build(lead, burn, money?(lead, burn))
          end
        end

        private

        def last_working_day_of_month?
          last = today.end_of_month
          last -= 1 until Assistant::Facts.working_day?(last)
          today == last
        end

        def quarter? = (today.month % 3).zero?

        def money?(lead, burn) = burn.planned.positive? && lead.allowed_in_project?(:view_budgets, project)

        def build(lead, burn, money)
          period = quarter? ? t("quarter", quarter: ((today.month - 1) / 3) + 1, year: today.year) : I18n.l(today, format: "%Y-%m")
          entries = TimeEntry.where(project:, spent_on: (quarter? ? today.beginning_of_quarter : today.beginning_of_month)..today)
          spent = money ? entries.sum("COALESCE(overridden_costs, costs)").to_f.round(2) : entries.sum(:hours).to_f.round(1)
          candidate(
            fingerprint: "#{today.year}-#{today.month}", recipient: lead, subject: project, nature: :team, channel: "brief",
            headline: t(money ? "headline_money" : "headline_hours", period:, spent:),
            because: [(money ? burn.because : t("hours_only", hours: burn.spent_hours, done: burn.done_percent)),
                      (t("ahead", points: burn.ahead_of_progress) if money && burn.ahead_of_progress.to_i.positive?),
                      t("by_person", list: burn.by_person.first(3).map { "#{it['user']} #{it['hours']} h" }.join(t("separator"))),
                      (forecast(burn) if money)].compact,
            impact: { money: money && burn.ahead_of_progress.to_i.positive? ? 3 : 0 },
            facts: { period:, money:, spent: }.merge(money ? { planned: burn.planned, spent_percent: burn.spent_percent } : {})
          )
        end

        # At the pace so far, when the money runs out.
        def forecast(burn)
          days = (today - project.created_at.to_date).to_i
          return if days <= 0 || burn.spent_money.zero?

          left = burn.planned - burn.spent_money
          return t("over", amount: (-left).round(2)) unless left.positive?

          t("runs_out", date: day(today + (left / (burn.spent_money / days)).round))
        end
      end
    end
  end
end
