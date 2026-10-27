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
  # Who may open a member's performance page in a project (05 §6): everyone
  # their own, others only with "view member performance".
  class PerformanceAccess
    def initialize(project, user)
      @project = project
      @user = user
    end

    attr_reader :project, :user

    def available? = Assistant::Surface.available?(project, user)

    def view_others? = available? && (user.admin? || user.allowed_in_project?(:view_member_performance, project))

    def appraise? = available? && user.allowed_in_project?(:appraise_members, project)

    def see?(subject) = available? && (subject == user || view_others?)
  end
end
