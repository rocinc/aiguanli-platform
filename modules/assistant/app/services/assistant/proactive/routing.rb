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
    # Who to tell first (03 §3.3). Someone's own slip goes to them alone; an
    # object's problem to whoever owns it; a team fact to whoever leads it.
    module Routing
      module_function

      LEAD_PERMISSIONS = %i[manage_versions edit_project].freeze

      # Named on the project's assistant preferences ("lead_ids"), or else
      # inferred: the people holding a role most members do not, among those
      # who may manage versions or the project. Administrators only when
      # nobody else is.
      def leads(project)
        named = ProjectSettings.for(project).lead_ids
        return people(project).select { named.include?(it.id) } if named.any?

        inferred_leads(project)
      end

      def inferred_leads(project)
        allowed = people(project).select { |user| LEAD_PERMISSIONS.any? { user.allowed_in_project?(it, project) } }
        humans = allowed.reject(&:admin?)
        roles = humans.to_h { [it, it.roles_for_project(project).map(&:id)] }
        common = roles.values.flatten.tally.select { |_, count| count > humans.size / 2 }.keys
        distinct = humans.select { (roles[it] - common).any? }
        distinct.presence || (humans.size <= 2 ? humans : []).presence || allowed.select(&:admin?)
      end

      def people(project)
        project.users.where(status: Principal.statuses[:active]).where.not(type: "AssistantUser").to_a
      end

      # Those work can be handed to: assignable in the platform's sense, able to edit
      # work packages, in at all today, and doing hands-on work here (time
      # logged, or a leaf work package assigned, open or done), which a product
      # owner holding only epics or the administrator account merely sitting in
      # the project is not.
      def assignable(project, on: Date.current)
        assignable_ids = Principal.possible_assignee(project).pluck(:id)
        hands_on = hands_on_ids(project)
        people(project).select do |user|
          assignable_ids.include?(user.id) && hands_on.include?(user.id) && user.allowed_in_project?(:edit_work_packages, project) &&
            available_on?(user, on)
        end
      end

      def hands_on_ids(project)
        logged = TimeEntry.where(project:).distinct.pluck(:user_id)
        parents = WorkPackage.where.not(parent_id: nil).select(:parent_id)
        leaves = WorkPackage.where(project:).where.not(assigned_to_id: nil).where.not(id: parents).distinct.pluck(:assigned_to_id)
        logged | leaves
      end

      def available_on?(user, date)
        hours = UserWorkingHours.for_user(user).valid_for_date(date)
        (hours.nil? || hours.availability_factor.to_i.positive?) &&
          UserNonWorkingTime.where(user:).where("start_date <= ? AND end_date >= ?", date, date).none?
      end

      def owner_of(work_package)
        [work_package.assigned_to, work_package.responsible].find { it.is_a?(User) && it.logged? && it.active? && !it.is_a?(AssistantUser) } ||
          leads(work_package.project).first
      end
    end
  end
end
