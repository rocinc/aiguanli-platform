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
  # Makes the assistant a member of a project with its own role, so that it
  # can be assigned, mentioned and can write through the platform services. What
  # it may do on someone's behalf is still bounded by that person (Preview runs
  # as them).
  module Membership
    module_function

    ROLE_NAME = "AI 助理"
    LEGACY_ROLE_NAME = "AI Assistant"
    PERMISSIONS = %i[
      view_project view_work_packages add_work_packages edit_work_packages manage_subtasks manage_work_package_relations
      add_work_package_comments view_internal_comments add_internal_comments edit_own_work_package_comments edit_own_messages work_package_assigned view_work_package_watchers add_work_package_watchers
      assign_versions change_work_package_status view_wiki_pages edit_wiki_pages view_messages add_messages
      view_meetings create_meetings manage_agendas manage_outcomes view_time_entries log_time view_members use_assistant
      view_sprints edit_sprints view_news comment_news view_documents view_calendar view_team_planner
      view_project_attributes view_budgets view_cost_rates view_own_hourly_rate
      edit_project manage_versions allocate_user_resources delete_work_packages edit_time_entries
    ].freeze

    # The role grows with what the assistant learns to do: permissions added
    # to PERMISSIONS later are given to an existing role too.
    def role
      found = ProjectRole.find_by(name: ROLE_NAME) || renamed_legacy_role
      found ||= ProjectRole.create!(name: ROLE_NAME, permissions: existing(PERMISSIONS))

      missing = existing(PERMISSIONS) - found.permissions
      found.add_permission!(*missing) if missing.any?
      copy_workflows(found)
      found
    end

    # Without workflows the assistant cannot move any work package between statuses.
    def copy_workflows(target)
      return if target.workflows.exists?

      source = workflow_source(target)
      return unless source

      Workflow.insert_all(source.workflows.map { it.attributes.except("id").merge("role_id" => target.id) })
    end

    def workflow_source(target)
      ProjectRole.where(builtin: Role::NON_BUILTIN).where.not(id: target.id)
                 .where(id: Workflow.select(:role_id)).max_by { it.permissions.size }
    end

    def renamed_legacy_role
      ProjectRole.find_by(name: LEGACY_ROLE_NAME)&.tap { it.update!(name: ROLE_NAME) }
    end

    def ensure_member!(project)
      member = Member.find_by(project:, principal: Assistant.user)
      return member if member&.roles&.include?(role)

      if member
        member.roles << role
        member
      else
        Member.create!(project:, principal: Assistant.user, roles: [role])
      end
    end

    def remove!(project)
      Member.where(project:, principal: Assistant.user).destroy_all
    end

    def existing(names)
      known = OpenProject::AccessControl.permissions.map(&:name)
      names.select { known.include?(it) }
    end
  end
end
