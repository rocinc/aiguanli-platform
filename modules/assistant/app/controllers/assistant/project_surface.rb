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
  # The project pages of the assistant: the project must be visible and the
  # assistant on there for this person. An archived project is only seen by
  # administrators, as elsewhere in the platform, and only read.
  module ProjectSurface
    extend ActiveSupport::Concern

    included do
      before_action :require_login
      before_action :find_assistant_project
      before_action :require_assistant_here
      before_action :require_writable_project, unless: -> { request.get? || request.head? }

      layout "base"
    end

    private

    def find_assistant_project
      @project = Project.find(params.expect(:project_id))
      render_404 unless @project.visible?(current_user) || (@project.archived? && current_user.admin?)
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def require_assistant_here
      return if archived_for_admin?

      deny_access unless Assistant::Surface.available?(@project, current_user)
    end

    def archived_for_admin? = @project.archived? && current_user.admin? && @project.module_enabled?(:assistant)

    def require_writable_project
      return unless @project.archived?

      respond_to do |format|
        format.turbo_stream { render turbo_stream: archived_notice, status: :unprocessable_entity }
        format.any do
          flash[:error] = t("assistant.project_pages.archived")
          redirect_back_or_to(project_overview_path(@project))
        end
      end
    end

    def require_project_permission(permission)
      return if archived_for_admin?

      deny_access unless current_user.allowed_in_project?(permission, @project)
    end

    def allowed?(permission) = !@project.archived? && current_user.allowed_in_project?(permission, @project)

    def read_only? = @project.archived?

    def archived_notice
      OpPrimer::FlashComponent.new(scheme: :danger, icon: :stop).with_content(t("assistant.project_pages.archived"))
                              .render_as_turbo_stream(view_context:, action: :flash)
    end

    def live_region(message)
      OpTurbo::StreamComponent.new(action: :liveRegion, message:, politeness: "polite", delay: nil, target: nil)
                              .render_in(view_context)
    end
  end
end
