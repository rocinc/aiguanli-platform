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
  # /my/performance: the same numbers the appraisers see, project by project.
  class MyPerformanceController < ApplicationController
    before_action :require_login
    before_action { deny_access unless Assistant::PanelDialogComponent.anywhere?(current_user) }
    authorization_checked! :show

    layout "my"
    menu_item :assistant_performance

    def show
      @page_view = Assistant::MyPerformanceComponent.new(user: current_user, projects:)
    end

    private

    def projects
      Project.active.has_module(:assistant).where(id: Member.where(user_id: current_user.id).select(:project_id))
             .select { Assistant::Surface.available?(it, current_user) }.sort_by(&:name)
    end
  end
end
