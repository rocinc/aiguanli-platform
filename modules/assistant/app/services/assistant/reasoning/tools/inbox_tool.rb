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
  module Reasoning
    module Tools
      class InboxTool < Base
        define "inbox_triage",
               "The person's unread notifications in the notification center, sorted into those that really need " \
               "them (they were given the work, mentioned, are asked a question or to do something, or it touches " \
               "something they promised) and those that can wait. Use for \"which of my notifications need me\", \"sort my " \
               "inbox\". Read-only: nothing is marked as read. Answer with the counts and one line per item that " \
               "needs them, each as #id with why; go deeper into an item only if asked."

        def call(_args)
          inbox = Assistant::InboxTriage.new(user)
          listed = inbox.items.first(Assistant::InboxTriage::LISTED).map { |entry| item(entry) }
          rest = inbox.ignorable
          { "unread" => inbox.unread.size,
            "needs_you" => { "count" => inbox.items.size, "items" => listed },
            "can_wait" => { "count" => rest.size, "by_reason" => rest.group_by(&:reason).transform_values(&:size) } }
        end

        private

        def item(entry)
          notification = entry.notification
          { "work_package" => wp_ref(notification.resource), "reason" => notification.reason, "why" => entry.why,
            "from" => notification.actor&.name, "at" => iso(notification.created_at.to_date) }
        end
      end
    end
  end
end
