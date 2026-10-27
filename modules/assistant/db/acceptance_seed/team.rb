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

module AssistantSeed
  class Team
    OWNER_EXTRAS = %i[manage_versions manage_assistant view_member_performance appraise_members].freeze

    def initialize(ctx)
      @ctx = ctx
    end

    def call
      restore_role_defaults
      assistant_workflows
      owner_hours
      memberships
      assistant_member
      time_off
      versions
      sprints
    end

    private

    def restore_role_defaults
      member = default_permissions(:default_role_member)
      reader = default_permissions(:default_role_reader)
      assign_permissions(Role.find_by!(name: "成员"), member)
      assign_permissions(Role.find_by!(name: "只读"), reader)
      assign_permissions(Role.find_by!(name: "产品负责人"), member | OWNER_EXTRAS)
    end

    def default_permissions(reference)
      docs = [Rails.root.join("app/seeders/common.yml"), *Rails.root.glob("modules/*/app/seeders/common.yml")]
             .map { YAML.unsafe_load_file(it) }
      base = docs.first["project_roles"].find { it["reference"] == reference }["permissions"]
      added = []
      removed = []
      docs.each do |doc|
        doc["modules_permissions"]&.each_value do |entries|
          entries.each do |entry|
            next unless entry["role"] == reference

            added.concat(Array(entry["add"]))
            removed.concat(Array(entry["remove"]))
          end
        end
      end
      known = OpenProject::AccessControl.permissions.map(&:name)
      ((base + added - removed) | OpenProject::AccessControl.public_permissions.map(&:name)).select { known.include?(it) }
    end

    def assign_permissions(role, permissions)
      list = with_dependencies(permissions)
      role.permissions = list
      role.save!
    end

    def with_dependencies(permissions)
      list = permissions.dup
      loop do
        before = list.size
        list |= list.flat_map { OpenProject::AccessControl.permission(it)&.dependencies.to_a }
        break if list.size == before
      end
      list
    end

    def assistant_workflows
      source = role("成员")
      assistant = Role.find_by(name: Assistant::Membership::ROLE_NAME) || Role.find_by!(name: Assistant::Membership::LEGACY_ROLE_NAME)
      [assistant, role("产品负责人")].each do |target|
        Workflow.where(role_id: target.id).delete_all
        rows = Workflow.where(role_id: source.id).map { it.attributes.except("id").merge("role_id" => target.id) }
        Workflow.insert_all(rows) if rows.any?
      end
    end

    def owner_hours
      ada = @ctx.user(:ada)
      UserWorkingHours.where(user: ada).delete_all
      UserWorkingHours.create!(user: ada, valid_from: @ctx.d(-100), monday: 480, tuesday: 480, wednesday: 480, thursday: 480,
                               friday: 480, saturday: 0, sunday: 0, availability_factor: 40)
      %i[ben bob fiona quinn].each do |key|
        user = @ctx.user(key)
        UserWorkingHours.where(user:).delete_all
        UserWorkingHours.create!(user:, valid_from: @ctx.d(-100), monday: 360, tuesday: 360, wednesday: 360, thursday: 360,
                                 friday: 360, saturday: 0, sunday: 0, availability_factor: 100)
      end
    end

    def role(name) = Role.find_by!(name:)

    def memberships
      project = @ctx.project
      targets = { sam: role("项目管理员"), ada: role("产品负责人") }
      %i[frank fiona bob ben mia].each { targets[it] = role("成员") }
      targets.each { |key, role| set_role(project, @ctx.user(key), role) }
      Member.where(project:, principal: @ctx.admin).destroy_all
      join_today(project, @ctx.user(:quinn), role("成员"))
    end

    def set_role(project, user, role)
      member = Member.find_or_initialize_by(project:, principal: user)
      member.member_roles.build(role:) if member.roles.exclude?(role)
      member.save!
      member.member_roles.where.not(role_id: role.id).destroy_all
    end

    def join_today(project, user, role)
      Member.where(project:, principal: user).destroy_all
      joined = @ctx.at(@ctx.monday, "08:30")
      member = Member.new(project:, principal: user)
      member.member_roles.build(role:)
      member.save!
      member.update_columns(created_at: joined, updated_at: joined)
      OpenProject::Notifications.send(OpenProject::Events::MEMBER_CREATED, member:)
      Assistant::Event.where(kind: "member_added", subject: user, project:).update_all(created_at: joined)
    end

    def assistant_member
      joined = @ctx.at(-70, "09:00")
      Member.where(project: @ctx.project, principal: Assistant.user).update_all(created_at: joined, updated_at: joined)
    end

    def time_off
      leave(:ben, @ctx.d(-7), @ctx.d(-3), booked: -21)
      leave(:frank, @ctx.d(-9), @ctx.d(60), booked: -30)
      leave(:mia, @ctx.d(-9), @ctx.d(60), booked: -30)
    end

    def leave(key, from, to, booked:)
      stamp = @ctx.at(booked, "10:00")
      UserNonWorkingTime.create!(user: @ctx.user(key), start_date: from, end_date: to, created_at: stamp, updated_at: stamp)
    end

    def versions
      Version.find(21).update!(name: "v1.1 商业化版", description: "用量计费、套餐升级与配额告警。", status: "open",
                               start_date: @ctx.d(-35), effective_date: @ctx.d(11))
      Version.find(22).update!(name: "v2.0 团队版", description: "协作编辑、导出与对外分享。", status: "open",
                               start_date: @ctx.d(7), effective_date: @ctx.d(67))
    end

    def sprints
      project = @ctx.project
      plan = { "Sprint 4" => [-35, -24, "completed"], "Sprint 5" => [-21, -10, "completed"],
               "Sprint 6" => [-7, 4, "active"], "Sprint 7" => [7, 18, "in_planning"] }
      plan.each do |name, (from, to, status)|
        sprint = Sprint.find_or_initialize_by(project:, name:)
        sprint.update!(start_date: @ctx.d(from), finish_date: @ctx.d(to), status:,
                       started_at: (@ctx.at(from, "09:30") unless status == "in_planning"),
                       completed_at: (@ctx.at(to, "17:30") if status == "completed"))
      end
    end
  end
end
