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
  class BriefsController < ApplicationController
    before_action :require_login
    before_action :find_optional_project
    before_action :check_access
    authorization_checked! :widget

    def widget
      brief = Assistant::Brief.new(user: current_user, project: @project)
      component = Assistant::BriefComponent.new(brief:, user: current_user, project: @project)
      render html: helpers.turbo_frame_tag(params[:frame].presence || "grids-widgets-assistant-today") {
        render_to_string(component, layout: false)
      }
    end

    private

    def check_access
      allowed = if @project then Assistant::Surface.available?(@project, current_user)
                else Assistant::PanelDialogComponent.anywhere?(current_user)
                end
      deny_access unless allowed
    end

    def find_optional_project
      @project = Project.find(params.expect(:project_id)) if params[:project_id].present?
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end
end
