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
  # Deterministic facts about a project. Every number is computed here, with
  # the reasoning that produced it, so that the model reasons over facts and
  # never does its own arithmetic.
  module Facts
    Fact = Data.define(:value, :because) do
      def to_h = { "value" => value, "because" => because }
    end

    module_function

    def working_day?(date) = calendar.working?(date)

    def working_days_between(from, to)
      return 0 if from.nil? || to.nil? || to < from

      (from..to).count { working_day?(it) }
    end

    def add_working_days(date, count)
      result = date
      step = count.negative? ? -1 : 1
      remaining = count.abs
      while remaining.positive?
        result += step
        remaining -= 1 if working_day?(result)
      end
      result
    end

    def next_working_day(date)
      date += 1
      date += 1 until working_day?(date)
      date
    end

    def work_packages_in(version) = WorkPackage.with_target_version(version.id)

    def version_ids_of(work_package_ids)
      WorkPackageVersion.where(kind: "target", work_package_id: work_package_ids)
                        .pluck(:work_package_id, :version_id).to_h
    end

    def version_of(work_package) = work_package.target_versions.first

    def current_sprint(project, on: Date.current)
      sprints = Sprint.where(project:).where.not(start_date: nil)
      sprints.where("start_date <= ? AND finish_date >= ?", on, on).order(:start_date).first ||
        sprints.where("start_date > ?", on).order(:start_date).first ||
        sprints.order(start_date: :desc).first
    end

    def next_sprint(sprint)
      Sprint.where(project_id: sprint.project_id).where("start_date > ?", sprint.finish_date || sprint.start_date)
            .order(:start_date).first
    end

    def open?(work_package) = !closed_status_ids.include?(work_package.status_id)

    # Hours left as entered; for sprint work estimated only in story points,
    # the points at what a point has cost this project so far.
    def remaining_hours(work_package)
      hours = work_package.remaining_hours || work_package.estimated_hours
      return hours.to_f if hours
      return 0.0 unless work_package.sprint_id && work_package.story_points.to_i.positive?

      (work_package.story_points * hours_per_point(work_package.project_id).to_f).round(1)
    end

    # Logged hours per story point over finished work that has both, the
    # median of at least four; nil when the project has no such history.
    def hours_per_point(project_id)
      RequestStore.fetch(:"assistant_hours_per_point_#{project_id}") do
        logged = TimeEntry.where(entity_type: "WorkPackage", project_id:).group(:entity_id).sum(:hours)
        ratios = WorkPackage.where(id: logged.keys, status_id: closed_status_ids).where("story_points > 0")
                            .pluck(:id, :story_points).filter_map { |id, points| logged[id].to_f / points if logged[id].to_f.positive? }
                            .sort
        ratios.size >= 4 ? ratios[ratios.size / 2].round(1) : nil
      end
    end

    def calendar = WorkPackages::Shared::WorkingDays.new

    # Per request: an administrator may close or reopen a status at any time.
    def closed_status_ids
      RequestStore.fetch(:assistant_closed_status_ids) { Status.where(is_closed: true).pluck(:id) }
    end

    def reset!
      RequestStore.store.delete_if { |key, _| key.to_s.start_with?("assistant_closed_status_ids", "assistant_hours_per_point") }
    end
  end
end
