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

# Called in an internal comment, the assistant could neither be offered as a
# mention nor read the thread it is answering.
class AddInternalCommentsToAssistantRole < ActiveRecord::Migration[8.0]
  PERMISSIONS = %i[view_internal_comments add_internal_comments].freeze

  def up
    ProjectRole.find_by(name: "AI Assistant")&.add_permission!(*PERMISSIONS)
  end

  def down
    role = ProjectRole.find_by(name: "AI Assistant") or return
    RolePermission.where(role_id: role.id, permission: PERMISSIONS.map(&:to_s)).delete_all
  end
end
