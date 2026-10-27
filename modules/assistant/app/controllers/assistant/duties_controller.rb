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
  # The standing jobs a project handed to the assistant. Anyone who may use
  # the assistant here reads them; handing one over takes a manager, changing
  # or taking one back takes the person who handed it over or a manager.
  # Every change answers by morphing the page in place, so focus stays on the
  # button that was pressed.
  class DutiesController < ApplicationController
    include Assistant::ProjectSurface

    before_action { require_project_permission(:use_assistant) }
    before_action(only: :create) { require_project_permission(:manage_assistant) }
    before_action :find_duty, only: %i[update destroy]
    before_action :require_operator, only: %i[update destroy]
    authorization_checked! :create, :update, :destroy

    menu_item :assistant

    def create
      return head(:unprocessable_entity) unless Assistant::Duty::KINDS.include?(params[:kind]) &&
                                                Assistant::Proactive::ProjectSettings.for(@project).duty_allowed?(params[:kind])

      duty = new_duty
      respond(t("assistant.duties_page.announce.#{duty.save ? 'created' : 'exists'}", duty: title(duty)))
    end

    def update
      @duty.update!(changes_from_params)
      respond(t("assistant.duties_page.announce.#{announcement}", duty: title(@duty)))
    end

    def destroy
      @duty.destroy!
      respond(t("assistant.duties_page.announce.removed", duty: title(@duty)))
    end

    private

    def find_duty
      @duty = Assistant::Duty.where(project: @project).find(params.expect(:id))
    end

    def new_duty
      Assistant::Duty.new(project: @project, kind: params[:kind], delegator: current_user,
                          scope: Assistant::DutyScope.permit(params[:kind], params[:scope], project: @project))
    end

    def require_operator
      return if archived_for_admin?

      deny_access unless @duty.delegator_id == current_user.id || current_user.allowed_in_project?(:manage_assistant, @project)
    end

    def changes_from_params
      changes = {}
      changes[:active] = ActiveModel::Type::Boolean.new.cast(params[:active]) if params.key?(:active)
      changes[:delegator] = current_user if params[:take_over].present?
      changes[:scope] = new_scope if params.key?(:scope)
      changes[:unseen_runs] = 0 if changes.key?(:active) || changes.key?(:scope) || params[:keep].present?
      changes
    end

    def new_scope = Assistant::DutyScope.permit(@duty.kind, params[:scope], project: @project)

    def announcement
      if params.key?(:active) then @duty.active? ? "resumed" : "paused"
      elsif params[:keep].present? then "kept"
      elsif params[:take_over].present? then "taken_over"
      else "saved"
      end
    end

    def title(duty) = t("assistant.duties.kinds.#{duty.kind}.title")

    def page_component = Assistant::DutiesPageComponent.new(project: @project, user: current_user, read_only: read_only?)

    def respond(message)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [turbo_stream.replace(Assistant::DutiesPageComponent::ID, page_component, method: :morph),
                                live_region(message)]
        end
        format.html do
          flash[:notice] = message
          redirect_to project_assistant_desk_path(@project, tab: "duties")
        end
      end
    end
  end
end
