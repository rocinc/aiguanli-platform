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
  module Duties
    # The duties a project starts with when the assistant is switched on (09
    # E4.1): the three that make the secretary look present. They are handed
    # over by whoever switched it on, at the most cautious level each has, and
    # are the team's to take back. A duty the project already has is left alone.
    module Defaults
      module_function

      KINDS = { "decision_log" => { "ceiling" => "draft" }, "meeting_followup" => {}, "onboarding" => {} }.freeze

      def ensure!(project, delegator)
        settings = Assistant::Proactive::ProjectSettings.for(project)
        KINDS.filter_map do |kind, scope|
          next unless settings.duty_allowed?(kind)

          Assistant::Duty.create_with(delegator:, scope:).find_or_create_by!(project:, kind:)
        rescue ActiveRecord::RecordNotUnique
          nil
        end
      end

      def enabler
        user = User.current
        user if user.is_a?(User) && user.logged? && user.active? && !user.is_a?(AssistantUser) && !user.is_a?(SystemUser)
      end
    end
  end
end
