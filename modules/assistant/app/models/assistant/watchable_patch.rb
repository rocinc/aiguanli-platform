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

module Assistant
  # The host offers only plain users as work package watchers
  # (`Principal.user` matches the type "User" exactly). The assistant is a
  # member like any other (01 §2.1), so it is offered too, where it may see
  # the work package.
  module WatchablePatch
    def possible_watcher_users
      sees = ::User.allowed_members_on_work_package(self.class.acts_as_watchable_permission, self)
      super.or(::User.where(id: ::AssistantUser.where(status: Principal.statuses[:active], id: sees).select(:id)))
    end
  end
end
