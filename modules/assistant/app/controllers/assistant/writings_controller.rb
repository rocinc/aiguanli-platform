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
  # The editor's writing menu and its runs. A run belongs to the person who
  # started it; nobody else can read or cancel it.
  class WritingsController < ApplicationController
    before_action :require_login
    before_action :find_context, only: %i[index create]
    before_action :find_run, only: %i[show cancel]
    authorization_checked! :index, :create, :show, :cancel

    def index
      actions = Setting.ai_text_transform_actions_enabled? ? Assistant::Writing.actions_for(user: current_user, project: @project, type: @type) : []
      render json: {
        enabled: Assistant::Llm.configured?,
        actions: actions.map { { id: it.id, label: it.label, template: it.injects_type_template } },
        built_in: built_in_keys.map { { key: it, label: t("assistant.writing.built_in.#{it}") } },
        glossary: Assistant::Writing.glossary_of(@project).present?
      }
    end

    def create
      return render_400 unless Assistant::Llm.configured?

      action = params[:action_id].presence && Setting.ai_text_transform_actions_enabled? && Assistant::Writing.actions_for(user: current_user, project: @project, type: @type)
                                                                .find { it.id == params[:action_id].to_i }
      built_in = params[:built_in].presence_in(Assistant::Writing::MODES.keys)
      return render_400 unless action || built_in
      return render_400 if built_in == "revise" && params[:previous].blank?
      return render_400 if built_in == "refine_selection" && (params[:selection].blank? || params[:instruction].blank?)

      run = Assistant::Writing.start(user: current_user, input: params.require(:input), action:, built_in:,
                                     instruction: params[:instruction], project: @project, type: @type,
                                     previous: params[:previous], selection: params[:selection],
                                     base: params[:base].presence_in(Assistant::Writing::BUILT_IN.keys),
                                     task_instruction: params[:task_instruction])
      render json: { id: run.uuid, status: run.status }, status: :created
    end

    # The events after `after`, so the editor can append text as it comes.
    def show
      events = @run.events_after(params[:after].to_i)
      render json: { id: @run.uuid, status: @run.status, error: @run.error_message,
                     events: events.map { { seq: it.seq, kind: it.kind, payload: it.payload } } }
    end

    def cancel
      @run.update!(cancel_requested: true) unless @run.terminal?
      head :no_content
    end

    private

    def built_in_keys
      Assistant::Writing::BUILT_IN.keys.reject do
        (it == "acceptance" && @type.nil?) || (it == "glossary" && Assistant::Writing.glossary_of(@project).blank?)
      end
    end

    def find_context
      @project = Project.visible(current_user).find_by(id: params[:project_id]) if params[:project_id].present?
      @type = ::Type.find_by(id: params[:type_id]) if params[:type_id].present?
      return render_403 if @project && !@project.module_enabled?(:assistant)
    end

    def find_run
      @run = AI::TextTransformRun.find_by(uuid: params[:id], user: current_user) or render_404
    end
  end
end
