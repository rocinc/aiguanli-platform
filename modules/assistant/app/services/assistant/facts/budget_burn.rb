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
  module Facts
    # How fast a project spends against its budgets and against its progress:
    # planned amount, spent so far, share of time elapsed, share of work done,
    # and where the spending goes. Hours stand in for money when no rates are
    # set, which is said in the because.
    class BudgetBurn
      def initialize(project, viewer:)
        @project = project
        @viewer = viewer
      end

      def budgets = @budgets ||= (defined?(::Budget) ? ::Budget.where(project: @project).to_a : [])

      def planned = budgets.sum { it.budget.to_f }.round(2)

      def spent_money = time_entries.sum("COALESCE(overridden_costs, costs)").to_f.round(2)

      def spent_hours = time_entries.sum(:hours).to_f.round(1)

      def done_percent
        all = work_packages.size
        return 0 if all.zero?

        (work_packages.count { !Facts.open?(it) } * 100.0 / all).round
      end

      def by_person
        time_entries.group(:user_id).sum(:hours).sort_by { -_2 }.first(6).map do |user_id, hours|
          { "user" => User.find_by(id: user_id)&.name, "hours" => hours.to_f.round(1) }
        end
      end

      def by_activity
        time_entries.joins(:activity).group("enumerations.name").sum(:hours).sort_by { -_2 }
                    .map { |name, hours| { "activity" => name, "hours" => hours.to_f.round(1) } }
      end

      def spent_percent
        return nil unless planned.positive?

        (spent_money * 100.0 / planned).round
      end

      def ahead_of_progress
        spent_percent && (spent_percent - done_percent)
      end

      def because
        if planned.positive?
          I18n.t("assistant.facts.budget.because", spent: spent_money, planned:, percent: spent_percent,
                                                   done: done_percent)
        else
          I18n.t("assistant.facts.budget.hours_only", hours: spent_hours, done: done_percent)
        end
      end

      def to_h
        { "budgets" => budgets.map { { "subject" => it.subject, "planned" => it.budget.to_f, "spent" => it.spent.to_f } },
          "planned" => planned, "spent" => spent_money, "spent_hours" => spent_hours, "spent_percent" => spent_percent,
          "done_percent" => done_percent, "spend_ahead_of_progress_points" => ahead_of_progress,
          "by_person" => by_person, "by_activity" => by_activity, "because" => because }
      end

      private

      def time_entries = TimeEntry.where(project: @project)

      def work_packages = @work_packages ||= WorkPackage.where(project: @project).to_a
    end
  end
end
