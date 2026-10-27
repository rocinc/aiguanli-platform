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
  # "You don't need to ask me for this kind of thing" (D3): turns a kind of
  # T2 change into T1 for the project, until someone takes it back. Lives on
  # the duties page.
  class GrantsController < ApplicationController
    include Assistant::ProjectSurface

    before_action { require_project_permission(:manage_assistant) }
    authorization_checked! :create, :destroy

    def create
      kind = params[:action_kind].to_s
      return head(:unprocessable_entity) unless Assistant::DutiesPageComponent.grantable_kinds(@project).include?(kind)

      unless Assistant::Grant.live.exists?(project: @project, action_kind: kind)
        Assistant::Grant.create!(project: @project, action_kind: kind, granted_by: current_user)
      end
      respond(t("assistant.grants.announce.granted", kind: Assistant::DutiesPageComponent.kind_label(kind)))
    end

    def destroy
      grant = Assistant::Grant.live.where(project: @project).find(params.expect(:id))
      grant.revoke!
      respond(t("assistant.grants.announce.revoked", kind: Assistant::DutiesPageComponent.kind_label(grant.action_kind)))
    end

    private

    def respond(message)
      respond_to do |format|
        format.turbo_stream do
          page = Assistant::DutiesPageComponent.new(project: @project, user: current_user, read_only: read_only?)
          render turbo_stream: [turbo_stream.replace(Assistant::DutiesPageComponent::ID, page, method: :morph),
                                live_region(message)]
        end
        format.html do
          flash[:notice] = message
          redirect_to project_assistant_desk_path(@project, tab: "duties", anchor: "assistant-grants")
        end
      end
    end
  end
end
