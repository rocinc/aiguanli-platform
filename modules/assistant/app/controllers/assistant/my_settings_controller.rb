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
  # /my/assistant: one page for how the assistant treats this person. Each
  # change answers by reloading the page's frame with one sentence next to
  # what changed.
  class MySettingsController < ApplicationController
    before_action :require_login
    before_action { deny_access unless Assistant::PanelDialogComponent.anywhere?(current_user) }
    authorization_checked! :show, :update, :unmute, :revoke

    layout "my"
    menu_item :assistant_settings

    def show
      @settings = Assistant::MySettings.new(current_user)
    end

    def update
      Assistant::MySettings.new(current_user).update!(settings_params)
      done("form", t("assistant.settings.saved"))
    end

    def unmute
      Assistant::MySettings.new(current_user).unmute!(params.expect(:rule), params[:project_id])
      done("mutes", t("assistant.settings.restored", rule: Assistant::MySettings.rule_title(params[:rule])))
    end

    def revoke
      grant = Assistant::MySettings.new(current_user).revoke!(params.expect(:id))
      done("grants", t("assistant.settings.revoked", kind: Assistant::DutiesPageComponent.kind_label(grant.action_kind),
                                                     project: grant.project.name))
    end

    private

    def settings_params
      params.permit(:proactivity, :interrupt_cap, :brief_email, project_levels: {})
    end

    def done(section, note)
      flash[:assistant_note] = { "section" => section, "text" => note }
      redirect_to my_assistant_path, status: :see_other
    end
  end
end
