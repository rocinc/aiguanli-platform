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

require Rails.root.join("db/migrate/migration_utils/permission_adder")

# Nobody could use the assistant: its permissions were declared but never
# given to a role. Whoever sees work packages may use it; whoever manages the
# project (edit_project) manages it and sees and appraises members (05 §6).
class GrantAssistantPermissions < ActiveRecord::Migration[8.0]
  def up
    adder = ::Migration::MigrationUtils::PermissionAdder
    adder.add(:view_work_packages, :use_assistant)
    adder.add(%i[edit_project], :manage_assistant)
    adder.add(%i[edit_project], :view_member_performance)
    adder.add(%i[edit_project], :appraise_members)
  end

  def down
    RolePermission.where(permission: %w[use_assistant manage_assistant view_member_performance appraise_members])
                  .where.not(role_id: ProjectRole.where(name: Assistant::Membership::ROLE_NAME).select(:id))
                  .delete_all
  end
end
