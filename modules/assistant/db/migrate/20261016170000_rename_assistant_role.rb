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

class RenameAssistantRole < ActiveRecord::Migration[8.0]
  def up
    old = ProjectRole.find_by(name: "AI Assistant") or return
    renamed = ProjectRole.find_by(name: "AI 助理")
    return old.update_columns(name: "AI 助理") unless renamed

    renamed.add_permission!(*old.permissions)
    MemberRole.where(role_id: old.id, member_id: MemberRole.where(role_id: renamed.id).select(:member_id)).delete_all
    MemberRole.where(role_id: old.id).update_all(role_id: renamed.id)
    old.reload.destroy!
  end

  def down
    ProjectRole.where(name: "AI 助理").update_all(name: "AI Assistant")
  end
end
