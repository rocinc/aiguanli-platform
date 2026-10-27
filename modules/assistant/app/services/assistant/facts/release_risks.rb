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
    # What stands between a version and its date, as lines a meeting can read:
    # work already overdue, the chain with no room left, the forecast against
    # the date, what waits on unfinished work, leave on a due date, and work
    # nobody owns. Every figure comes from the readiness and schedule
    # calculations; each line names its work packages so they link.
    class ReleaseRisks
      LIMIT = 5
      TITLE = 22
      CHAIN_SLACK = 2

      def initialize(readiness, today: Date.current, graph: nil)
        @readiness = readiness
        @version = readiness.version
        @today = today
        @graph = graph || ScheduleGraph.new(@version.project)
      end

      # [[kind, line]], most pressing first.
      def lines
        [*overdue, *chain, *forecast, *blocked, *leave_on_due_date, *unassigned]
      end

      def self.ref(id, subject) = t("ref", ref: "##{id}", title: subject.to_s.truncate(TITLE))

      def self.refs(work_packages) = work_packages.first(LIMIT).map { ref(it.id, it.subject) }.join(t("separator"))

      def self.t(key, **) = I18n.t("assistant.facts.release_risks.#{key}", **)

      # { work package id => [open work packages it waits on] }
      def self.waiting_on(work_packages)
        ids = work_packages.map(&:id)
        pairs = Relation.where(to_id: ids, relation_type: "blocks").pluck(:to_id, :from_id) +
                Relation.where(from_id: ids, relation_type: "follows").pluck(:from_id, :to_id)
        open = WorkPackage.where(id: pairs.map(&:last)).where.not(status_id: Facts.closed_status_ids).index_by(&:id)
        pairs.select { open.key?(it.last) }.group_by(&:first).transform_values { |list| list.map { open[it.last] }.uniq }
      end

      def self.blocked_lines(work_packages, limit: 3)
        waiting = waiting_on(work_packages)
        work_packages.select { waiting.key?(it.id) }.first(limit).map do |wp|
          t("blocked", ref: ref(wp.id, wp.subject), by: refs(waiting[wp.id]))
        end
      end

      def self.unassigned_line(work_packages, key: "unassigned", **)
        t(key, list: refs(work_packages), **) if work_packages.any?
      end

      private

      attr_reader :readiness, :version, :today, :graph

      def line(kind, text) = [kind, text]

      def overdue
        return [] if readiness.overdue.empty?

        [line(:overdue, self.class.t("overdue", list: self.class.refs(readiness.overdue)))]
      end

      def chain
        tight = graph.critical_chain(version).select { (slack = graph.slack(it.id)) && slack <= CHAIN_SLACK }
        return [] if tight.empty?

        worst = tight.map { graph.slack(it.id) }.max
        ids = tight.map { "##{it.id}" }
        text = if tight.one?
                 self.class.t("margin", ref: ids.first, slack: worst)
               else
                 self.class.t(worst.positive? ? "chain_thin" : "chain_none", chain: ids.join("→"), slack: worst, version: version.name)
               end
        [line(:margin, text)]
      end

      def forecast
        date = version.effective_date or return []
        finish = readiness.forecast_finish
        vars = { version: version.name, date: Assistant::Text.day(date) }
        if finish && finish > date
          [line(:forecast, self.class.t("forecast_late", **vars, finish: Assistant::Text.day(finish),
                                                          days: Facts.working_days_between(date + 1, finish)))]
        elsif finish
          [line(:forecast, self.class.t("forecast_ok", **vars, finish: Assistant::Text.day(finish)))]
        elsif readiness.slip_days.positive?
          [line(:forecast, self.class.t("planned_late", **vars, finish: Assistant::Text.day(readiness.planned_finish),
                                                         days: readiness.slip_days))]
        else
          []
        end
      end

      def blocked
        self.class.blocked_lines(readiness.open).map { line(:blocked, it) }
      end

      def leave_on_due_date
        dated = readiness.open.select { it.assigned_to_id && it.due_date }.sort_by(&:due_date)
        leave = UserNonWorkingTime.where(user_id: dated.map(&:assigned_to_id).uniq).group_by(&:user_id)
        dated.filter_map do |wp|
          away = leave[wp.assigned_to_id]&.detect { (it.start_date..it.end_date).cover?(wp.due_date) } or next
          line(:leave, self.class.t("leave", ref: self.class.ref(wp.id, wp.subject), due: short(wp.due_date), name: wp.assigned_to.name,
                                             span: span(away.start_date, away.end_date)))
        end.first(3)
      end

      def unassigned
        text = self.class.unassigned_line(readiness.unassigned)
        text ? [line(:unassigned, text)] : []
      end

      def short(date) = I18n.l(date, format: "%-m/%-d")

      def span(from, to) = from == to ? short(from) : "#{short(from)}–#{short(to)}"
    end
  end
end
