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
  # The assistant's desk in a project: what it watches for this person, the
  # jobs handed to it, the ideas people mentioned and how it is doing. The
  # tabs are a closed set; each one shows the page that used to stand alone.
  class DeskController < ApplicationController
    include Assistant::ProjectSurface

    before_action { require_project_permission(:use_assistant) }
    before_action :find_tab, only: :show
    authorization_checked! :show, :pause, :resume

    menu_item :assistant

    def show
      @desk = Assistant::DeskComponent.new(project: @project, user: current_user, tab: @tab, tabs: tabs,
                                           read_only: read_only?)
    end

    def pause
      length = params[:length].to_s
      return head(:unprocessable_entity) unless length.in?(Assistant::Pause::LENGTHS)

      until_time = Assistant::Pause.until_for(length, current_user)
      Assistant::Preference.for(current_user).pause_until!(until_time)
      redirect_to project_assistant_desk_path(@project, tab: tab_param)
    end

    def resume
      Assistant::Preference.for(current_user).resume!
      redirect_to project_assistant_desk_path(@project, tab: tab_param)
    end

    private

    def tab_param = params.permit(:tab)[:tab].presence_in(Assistant::DeskComponent::TABS)

    def tabs = Assistant::DeskComponent::TABS

    def find_tab
      @tab = tab_param || Assistant::DeskComponent::TABS.first
    end
  end
end
