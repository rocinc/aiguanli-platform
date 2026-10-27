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
    # How ready a version is: scope done, what is still open, what blocks it,
    # open defects, the latest planned finish against its date, how much
    # slack is left, and when it finishes at the pace of the last four weeks
    # (04 A4 就绪度、按当前速度的预计完成日).
    class VersionReadiness
      def initialize(version, today: Date.current)
        @version = version
        @today = today
      end

      attr_reader :version

      def work_packages = @work_packages ||= Facts.work_packages_in(version).includes(:status, :assigned_to).to_a

      def open = work_packages.reject { Facts.closed_status_ids.include?(it.status_id) }

      def done_ratio
        return 0 if work_packages.empty?

        ((work_packages.size - open.size) * 100.0 / work_packages.size).round
      end

      def planned_finish = open.filter_map(&:due_date).max

      def days_left = version.effective_date && Facts.working_days_between(@today, version.effective_date)

      def slip_days
        return 0 unless version.effective_date && planned_finish && planned_finish > version.effective_date

        Facts.working_days_between(version.effective_date + 1, planned_finish)
      end

      def overdue = open.select { it.due_date && it.due_date < @today }

      def unassigned = open.select { it.assigned_to_id.nil? }

      def unscheduled = open.select { it.due_date.nil? }

      def at_risk? = slip_days.positive? || overdue.any?

      # Open work waiting on other open work that is not done yet.
      def blocked
        @blocked ||= begin
          ids = open.map(&:id)
          blocking = Relation.where(to_id: ids, relation_type: "blocks").pluck(:to_id, :from_id) +
                     Relation.where(from_id: ids, relation_type: "follows").pluck(:from_id, :to_id)
          still_open = WorkPackage.where(id: blocking.map(&:last)).where.not(status_id: Facts.closed_status_ids).pluck(:id).to_set
          waiting = blocking.select { still_open.include?(it.last) }.map(&:first).to_set
          open.select { waiting.include?(it.id) }
        end
      end

      def open_defects
        types = Type.all.select { |type| SprintHistory::DEFECT_TYPES.any? { type.name.downcase.include?(it) } }.map(&:id)
        open.select { types.include?(it.type_id) }
      end

      PACE_WORKING_DAYS = 20

      # Closed items of this version per working day over the last four
      # weeks (closing time read as the last update), nil when none closed.
      def pace
        from = Facts.add_working_days(@today, -PACE_WORKING_DAYS)
        closed = (work_packages - open).count { it.updated_at.to_date > from }
        closed.positive? ? closed.fdiv(PACE_WORKING_DAYS) : nil
      end

      def forecast_finish
        return @today if open.empty?

        pace && Facts.add_working_days(@today, (open.size / pace).ceil)
      end

      def because
        I18n.t("assistant.facts.version.because", name: version.name, done: done_ratio, open: open.size,
                                                  finish: planned_finish ? Assistant::Text.day(planned_finish) : "–",
                                                  date: version.effective_date ? Assistant::Text.day(version.effective_date) : "–")
      end

      def to_h
        { "version" => version.name, "date" => version.effective_date&.iso8601, "done_percent" => done_ratio,
          "open" => open.size, "planned_finish" => planned_finish&.iso8601, "slip_working_days" => slip_days,
          "overdue" => overdue.map { "##{it.id} #{it.subject}" }, "unassigned" => unassigned.size,
          "unscheduled" => unscheduled.size, "blocked" => blocked.map { "##{it.id}" },
          "open_defects" => open_defects.size, "forecast_finish" => forecast_finish&.iso8601, "because" => because }
      end
    end
  end
end
