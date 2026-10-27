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
  module Actions
    # Who may confirm a proposed action: the person it is for, if the preview
    # passes as them, or anyone who may edit everything it touches.
    class Authority
      def initialize(action, user)
        @action = action
        @user = user
      end

      def may_decide?
        return false if user.anonymous? || user.is_a?(AssistantUser)
        return true if user.admin?
        return false if action.project && !user.allowed_in_project?(:use_assistant, action.project)

        user.id == action.on_behalf_of_id || may_edit_all?
      end

      private

      attr_reader :action, :user

      def may_edit_all?
        action.steps.all? do |step|
          target = Steps.for(step).target
          case target
          when WorkPackage then user.allowed_in_work_package?(:edit_work_packages, target)
          when Project then user.allowed_in_project?(:edit_project, target)
          else action.project && user.allowed_in_project?(:edit_work_packages, action.project)
          end
        end
      end
    end
  end
end
