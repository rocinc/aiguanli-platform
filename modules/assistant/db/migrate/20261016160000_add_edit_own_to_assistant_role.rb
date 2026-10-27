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

# The line the assistant leaves when it is called is later replaced by the
# answer, which is an edit of its own comment or reply.
class AddEditOwnToAssistantRole < ActiveRecord::Migration[8.0]
  PERMISSIONS = %i[edit_own_work_package_comments edit_own_messages].freeze

  def up
    ProjectRole.find_by(name: "AI Assistant")&.add_permission!(*PERMISSIONS)
  end

  def down
    role = ProjectRole.find_by(name: "AI Assistant") or return
    RolePermission.where(role_id: role.id, permission: PERMISSIONS.map(&:to_s)).delete_all
  end
end
