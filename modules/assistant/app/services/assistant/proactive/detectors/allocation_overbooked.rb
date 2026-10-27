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
      # A resource allocation in this project leaves someone booked beyond
      # their working time (04 B4, the platform's own overbooking check). Whoever
      # approved it (reviewed_by, else who requested it) hears it with the ways
      # out. When the overbooking comes from several projects (04 E3), this
      # project's leads hear it too; every project involved runs the same
      # sweep, so each of their leads hears it once.
      class AllocationOverbooked < Base
        def candidates
          return [] unless defined?(::ResourceAllocation)

          overbooked.flat_map do |principal, ranges, allocations|
            range = ranges.max_by(&:over_by_minutes)
            projects = Project.where(id: WorkPackage.where(id: range.work_package_ids).select(:project_id)).to_a
            recipients = approvers(allocations)
            recipients |= leads if projects.size > 1
            recipients.reject { it == principal }.map { build(principal, range, projects, allocations, it) }
          end
        end

        private

        # [[user, overbooked ranges, this project's allocations in them]]
        def overbooked
          mine = ::ResourceAllocation.allocated.for_project(project).where(end_date: today..).where.not(principal_id: nil)
                                     .includes(:principal, :entity, :reviewed_by, :requested_by).to_a
          mine.group_by(&:principal).filter_map do |principal, allocations|
            next unless principal.is_a?(User) && principal.active?

            ranges = ::ResourceAllocations::Availability.new(user: principal).overbooked_ranges
                                                        .select { it.end_date >= today }
            hit = allocations.select { |a| ranges.any? { |r| a.start_date <= r.end_date && a.end_date >= r.start_date } }
            [principal, ranges, hit] if hit.any?
          end
        end

        def approvers(allocations)
          allocations.filter_map { it.reviewed_by || it.requested_by }.uniq.select { it.active? && !it.is_a?(AssistantUser) }
                     .presence || leads.first(1)
        end

        def build(principal, range, projects, allocations, approver)
          over = (range.over_by_minutes / 60.0).round(1)
          candidate(
            fingerprint: "#{principal.id}:#{range.start_date}:#{range.over_by_minutes}", recipient: approver, subject: project,
            nature: :team,
            headline: t("headline", name: principal.name, hours: over, from: day(range.start_date), to: day(range.end_date)),
            because: [t("booked", available: (range.available_minutes.to_i / 60.0).round(1), over:),
                      t("here", list: allocations.map { "##{it.entity_id}" }.uniq.join(t("separator"))),
                      (if (projects - [project]).any?
                         t("elsewhere",
                           list: (projects - [project]).map(&:name).join(t("separator")))
                       end)].compact,
            impact: { people: 1, cascade: allocations.size }, act_by: range.start_date,
            facts: { user_id: principal.id, over_hours: over, from: range.start_date, to: range.end_date,
                     projects: projects.map(&:id), allocation_ids: allocations.map(&:id) },
            steps_for: ->(_user) { options(principal, allocations, range) }
          )
        end

        def options(principal, allocations, range)
          allocations.first(2).filter_map do |allocation|
            wp = allocation.entity
            next unless wp.is_a?(WorkPackage)

            hours = (allocation.allocated_time / 60.0).round(1)
            helper, free = free_member(range.start_date, range.end_date, hours, except: [principal.id])
            next unless helper

            option(t("hand_over", ref: "##{wp.id}", name: helper.name), t("hand_over_consequence", name: helper.name, free:),
                   "reallocate", [{ "op" => "create_resource_allocation", "type" => "WorkPackage", "id" => wp.id,
                                    "attributes" => { "work_package_id" => wp.id, "user_id" => helper.id, "hours" => hours,
                                                      "start_date" => allocation.start_date.iso8601,
                                                      "end_date" => allocation.end_date.iso8601 } }])
          end
        end
      end
    end
  end
end
