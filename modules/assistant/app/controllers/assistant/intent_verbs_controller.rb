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
  # The verbs of a remembered thing (see IntentVerbs): the panel a verb opens,
  # the preview before a change that touches others, doing it, and taking
  # back a set-aside. A finished verb answers with the row itself, so the
  # receipt or draft appears right where the thing is listed.
  class IntentVerbsController < ApplicationController
    before_action :require_login
    before_action :find_intent
    before_action :find_meeting
    before_action :find_verbs
    authorization_checked! :show, :preview, :act, :undo

    def show
      render_panel
    end

    def preview
      result = act_with(confirm: false).preview
      result.state == :preview ? render_panel(trial: result.trial) : respond_with(result)
    end

    def act
      result = act_with(confirm: params[:confirm] == "1").call
      respond_with(result)
    end

    def undo
      Assistant::IntentVerbs::Act.unshelve(@intent)
      render turbo_stream: replace_row
    end

    private

    def find_intent
      @intent = Assistant::Intent.visible(current_user).includes(:project).find(params.expect(:intent_id))
      deny_access unless Assistant::Surface.available?(@intent.project, current_user)
    end

    def find_meeting
      @meeting = ::Meeting.visible(current_user).find_by(id: params[:context_meeting_id], project_id: @intent.project_id)
    end

    def find_verbs = @verbs = Assistant::IntentVerbs.new(@intent, current_user, meeting: @meeting, lead:)

    def density = params[:density].to_s == "compact" ? :compact : :regular

    def lead = params[:lead].presence_in(Assistant::IntentVerbs::ORDER.values.flatten)

    def act_with(confirm:)
      Assistant::IntentVerbs::Act.new(@verbs, params[:verb], verb_params, confirm:)
    end

    def verb_params = params.slice(*Assistant::IntentVerbs::Act::PARAMS).permit(*Assistant::IntentVerbs::Act::PARAMS).to_h

    def respond_with(result)
      case result.state
      when :refused then render_panel(message: result.message)
      when :preview then render_panel(trial: result.trial)
      else render turbo_stream: replace_row(result)
      end
    end

    def render_panel(trial: nil, message: nil)
      verb = params[:verb].to_s
      return head(:not_found) unless Assistant::IntentVerbs::ORDER.values.flatten.include?(verb)

      panel = Assistant::IntentVerbPanelComponent.new(verbs: @verbs, verb:, user: current_user, params: verb_params, trial:,
                                                      message:, density:, lead:)
      render panel, layout: false
    end

    def replace_row(result = nil)
      component = Assistant::IntentVerbsComponent.new(intent: @intent.reload, user: current_user, meeting: @meeting, result:,
                                                      density:, lead:)
      turbo_stream.replace(Assistant::IntentVerbsComponent.frame_id(@intent), component)
    end
  end
end
