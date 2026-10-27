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
  class Notebook
    IDENTIFIER = Reset::SECOND_IDENTIFIER

    def initialize(ctx)
      @ctx = ctx
    end

    def call
      User.current = @ctx.user(:sam)
      project = Project.find_or_initialize_by(identifier: IDENTIFIER)
      project.assign_attributes(name: "产品调研笔记", description: "记录对写作产品的调研想法，目前只有几件事。", public: false, workspace_type: "project")
      project.enabled_module_names = %w[work_package_tracking assistant]
      project.save!
      @ctx.retime(project, @ctx.at(-3, "10:00"))
      [TYPES[:task], TYPES[:story], TYPES[:bug]].each { ProjectType.find_or_create_by!(project:, type_id: it) }
      members(project)
      work_packages(project)
      Assistant::Membership.ensure_member!(project)
      Member.where(project:, principal: Assistant.user).update_all(created_at: @ctx.at(@ctx.today, "08:20"),
                                                                   updated_at: @ctx.at(
                                                                     @ctx.today, "08:20"
                                                                   ))
      Assistant::Duties::Defaults.ensure!(project, @ctx.user(:sam))
      Assistant::Proactive::ProjectSettings.write!(project, lead_ids: [@ctx.user(:sam).id])
    end

    private

    def members(project)
      { sam: "项目管理员", fiona: "成员" }.each do |key, role_name|
        member = Member.find_or_initialize_by(project:, principal: @ctx.user(key))
        member.member_roles.build(role: Role.find_by!(name: role_name)) unless member.persisted?
        member.save!
        member.update_columns(created_at: @ctx.at(-3, "10:00"), updated_at: @ctx.at(-3, "10:00"))
      end
    end

    def work_packages(project)
      [
        ["整理竞品功能对比表", :task, :sam, :confirmed, 4, "把三款竞品的写作功能列成一张表，标出我们没有的。"],
        ["访谈 5 位写作者，梳理写作痛点", :story, :fiona, :new, 9, "约 5 位经常写长文的用户，各聊半小时。"],
        ["确定调研结论的汇报格式", :task, :sam, :new, nil, "先定是写一页纸还是做一次分享。"]
      ].each do |subject, type, who, status, due, text|
        User.current = @ctx.user(:sam)
        stamp = @ctx.at(-3, "11:00")
        WorkPackage.create!(project:, subject:, type_id: TYPES.fetch(type), status_id: STATUSES.fetch(status), priority_id: PRIORITIES[:normal],
                            author: @ctx.user(:sam), assigned_to: @ctx.user(who), due_date: (@ctx.backward(@ctx.d(due)) if due),
                            description: text, schedule_manually: true, created_at: stamp, updated_at: stamp)
      end
    end
  end
end
