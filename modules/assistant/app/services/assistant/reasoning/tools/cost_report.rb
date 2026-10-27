# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  module Reasoning
    module Tools
      # A cost report from one sentence (04 C3): a period, the project or one
      # of its versions, grouped by person, activity, work package or month.
      # Hours come from what the asker may see; money only where they may also
      # see the rates, and the answer says when it left money out.
      class CostReport < Base
        GROUPS = %w[person activity work_package month].freeze
        MAX_ROWS = 15

        define "cost_report",
               "Hours and costs booked in this project for a period, optionally for one version, grouped by " \
               "person, activity, work package or month. Money is only included where the asker may see rates.",
               { from: { type: "string", description: "First day, YYYY-MM-DD; defaults to the first of this month" },
                 to: { type: "string", description: "Last day, YYYY-MM-DD; defaults to today" },
                 version: { type: "string", description: "Version name or id, to count only its work packages" },
                 group_by: { type: "string", enum: GROUPS, description: "Defaults to person" } }

        def call(args)
          raise Refused, I18n.t("assistant.reasoning.errors.not_allowed") unless allowed?

          from = context.date(args["from"], default: Date.current.beginning_of_month)
          to = context.date(args["to"], default: Date.current)
          version = args["version"].presence && context.version(args["version"])
          group = GROUPS.include?(args["group_by"]) ? args["group_by"] : "person"
          report(scoped(TimeEntry.visible(user, project), from, to, version), from, to, version, group)
        end

        private

        def allowed?
          %i[view_time_entries view_own_time_entries view_cost_entries view_own_cost_entries]
            .any? { user.allowed_in_project?(it, project) }
        end

        def money? = user.allowed_in_project?(:view_hourly_rates, project) || user.allowed_in_project?(:view_cost_rates, project)

        def scoped(scope, from, to, version)
          scope = scope.where(spent_on: from..to)
          return scope unless version

          scope.where(entity_type: "WorkPackage", entity_id: WorkPackage.with_target_version(version.id).select(:id))
        end

        def report(entries, from, to, version, group)
          costed = money? ? TimeEntry.visible_costs(user, project).merge(entries) : TimeEntry.none
          rows = grouped(entries, group).map { |key, hours| row(key, hours, group, costed) }
          hours = entries.sum(:hours).to_f.round(1)
          total = money? ? sum_money(costed) : nil
          { "from" => from.iso8601, "to" => to.iso8601, "version" => version&.name, "grouped_by" => group,
            "hours" => hours, "money" => total, "material" => material(from, to, version),
            "rows" => rows.first(MAX_ROWS), "more_rows" => [rows.size - MAX_ROWS, 0].max,
            "currency" => Setting.costs_currency, "budget" => budget(version),
            "note" => note(hours, total) }.compact
        end

        # Zero money on booked hours means no rates were set, not free work.
        def note(hours, total)
          if !money? then I18n.t("assistant.reasoning.cost_report.no_rates")
          elsif total.zero? && hours.positive? then I18n.t("assistant.reasoning.cost_report.rates_unset")
          end
        end

        def grouped(entries, group)
          column = { "person" => :user_id, "activity" => :activity_id, "work_package" => :entity_id,
                     "month" => Arel.sql("DATE_TRUNC('month', spent_on)") }.fetch(group)
          entries.group(column).sum(:hours).sort_by { -it.last }
        end

        def row(key, hours, group, costed)
          label = label_for(key, group)
          money = money? ? sum_money(costed.where(group_condition(key, group))) : nil
          { "label" => label, "hours" => hours.to_f.round(1), "money" => money }.compact
        end

        def group_condition(key, group)
          case group
          when "person" then { user_id: key }
          when "activity" then { activity_id: key }
          when "work_package" then { entity_type: "WorkPackage", entity_id: key }
          else { spent_on: key.to_date.all_month }
          end
        end

        def label_for(key, group)
          case group
          when "person" then User.find_by(id: key)&.name || I18n.t("assistant.reasoning.cost_report.unknown")
          when "activity" then TimeEntryActivity.find_by(id: key)&.name || I18n.t("assistant.reasoning.cost_report.unknown")
          when "work_package" then WorkPackage.visible(user).find_by(id: key)&.then { "##{it.id} #{it.subject}" } ||
                                   I18n.t("assistant.reasoning.cost_report.hidden")
          else I18n.l(key.to_date, format: "%Y-%m")
          end
        end

        def sum_money(scope) = scope.sum("COALESCE(time_entries.overridden_costs, time_entries.costs)").to_f.round(2)

        def material(from, to, version)
          return unless defined?(::CostEntry) && user.allowed_in_project?(:view_cost_rates, project)

          scope = scoped(::CostEntry.visible_costs(user, project), from, to, version)
          { "units" => scope.sum(:units).to_f.round(2),
            "money" => scope.sum("COALESCE(cost_entries.overridden_costs, cost_entries.costs)").to_f.round(2) }
        end

        def budget(version)
          return if version || !user.allowed_in_project?(:view_budgets, project)

          Assistant::Facts::BudgetBurn.new(project, viewer: user).to_h.slice("planned", "spent", "spent_percent",
                                                                             "done_percent")
        end
      end
    end
  end
end
