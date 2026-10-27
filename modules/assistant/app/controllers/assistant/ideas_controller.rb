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
  # What people said in passing, kept in the desk's Ideas tab. Nothing here
  # is a to-do and nothing reminds anyone. An idea can be turned into a work
  # package, which keeps where it came from, merged into another one that
  # says the same, or set aside; set aside, it can be taken back.
  class IdeasController < ApplicationController
    include Assistant::ProjectSurface

    before_action { require_project_permission(:use_assistant) }
    before_action :find_idea
    before_action { require_project_permission(:add_work_packages) if action_name == "convert" }
    authorization_checked! :convert, :merge, :release, :restore

    menu_item :assistant

    # Turning an idea into a work package goes through the action layer like
    # any other change: previewed as the person, done as the assistant, with
    # its provenance and undo.
    def convert
      return respond(t("assistant.ideas.announce.taken"), success: false) unless @idea.state == "open"

      action = propose
      result = Assistant::Decisions.new(action, user: current_user).approve if action.proposed?
      return respond(failure_message(action, result), success: false) unless result&.ok

      adopt!(action.reload)
      respond(t("assistant.ideas.announce.converted", ref: "##{@idea.work_package_id}"))
    end

    def merge
      target = merge_target
      return respond(t("assistant.ideas.announce.taken"), success: false) unless @idea.state == "open" && target

      @idea.merge_into!(target)
      @focus = target
      respond(t("assistant.ideas.announce.merged", title: title_of(@idea), into: title_of(target)))
    end

    def release
      return respond(t("assistant.ideas.announce.taken"), success: false) unless @idea.state == "open"

      @idea.set_aside!(params[:reason])
      respond(t("assistant.ideas.announce.released", title: title_of(@idea)))
    end

    def restore
      unless @idea.state == "set_aside" || (@idea.state == "adopted" && @idea.work_package_id.nil?)
        return respond(t("assistant.ideas.announce.taken"), success: false)
      end

      @idea.reopen!
      respond(t("assistant.ideas.announce.restored", title: title_of(@idea)))
    end

    private

    def find_idea
      @idea = Assistant::Idea.where(project: @project).find(params.expect(:id))
      return render_404 unless entry.shown?

      @focus = @idea
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def merge_target
      target = Assistant::Idea.open.where(project: @project).where.not(id: @idea.id).find_by(id: params[:into_id])
      target if target && Assistant::Ideas::Entry.new(target, current_user).shown?
    end

    def entry = Assistant::Ideas::Entry.new(@idea, current_user)

    def title_of(idea) = (Assistant::Ideas::Entry.new(idea, current_user).title || idea.title).truncate(60)

    def page_component
      Assistant::Desk::IdeasComponent.new(project: @project, user: current_user, read_only: read_only?, focus: @focus&.id)
    end

    def propose
      Assistant::Actions::Propose.call(
        kind: "idea_to_work_package", title: t("assistant.ideas.action_title", title: title_of(@idea)),
        steps: Assistant::Proactive::Detectors::IdeaGarden.work_package_steps(@idea, current_user), on_behalf_of: current_user,
        project: @project, basis: entry.basis, auto_execute: false
      )
    end

    def failure_message(action, result)
      result&.message || action.error.presence || t("assistant.card.failed_generic")
    end

    # Until the detector does it on execution: the idea points at the work
    # package it became, so it is not raised again.
    def adopt!(action)
      created = Array(action.inverse).find { it["created"] && it["type"] == "WorkPackage" }
      @idea.update!(state: "adopted", work_package_id: created&.dig("id") || @idea.work_package_id)
    end

    def respond(message, success: true)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [turbo_stream.replace(Assistant::Desk::IdeasComponent::ID, page_component, method: :morph),
                                live_region(message)],
                 status: success ? :ok : :unprocessable_entity
        end
        format.html do
          flash[success ? :notice : :error] = message
          redirect_to project_assistant_desk_path(@project, tab: "ideas", anchor: "assistant-idea-#{@focus.id}")
        end
      end
    end
  end
end
