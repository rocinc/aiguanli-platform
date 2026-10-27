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

class Projects::Settings::AssistantController < Projects::SettingsController
  menu_item :settings_assistant

  def show
    @settings = ::Assistant::ProjectPage.new(@project)
  end

  def update
    ::Assistant::ProjectPage.new(@project).update!(page_params)
    flash[:assistant_saved] = true
    redirect_to project_settings_assistant_path(@project), status: :see_other
  end

  private

  def page_params
    params.permit(:level, :token_cap, role_levels: {}, rules: [], lead_ids: [], duties: [])
  end
end
