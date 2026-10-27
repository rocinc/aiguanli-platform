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
  # A member's performance (05). Everyone sees their own page, which shows
  # exactly the numbers an appraiser sees, who looked at it, and lets them add
  # their side. Seeing others needs "view member performance"; drafting and
  # finalising the written appraisal needs "appraise members".
  class PerformanceController < ApplicationController
    include Assistant::ProjectSurface

    PERIODS = { "30" => 30, "90" => 90, "180" => 180 }.freeze
    DEFAULT_PERIOD = "90"

    before_action :find_subject, only: %i[show draft finalize note]
    before_action :authorize_view, only: %i[team show]
    before_action -> { require_project_permission(:appraise_members) }, only: %i[draft finalize]
    before_action :authorize_note, only: %i[note]
    authorization_checked! :team, :show, :draft, :finalize, :note

    menu_item :members

    def team
      @page_view = Assistant::AppraisalsTeamComponent.new(team: appraisal_team, user: current_user, period: period_key,
                                                          periods: PERIODS.keys, sort: params[:sort])
    end

    def show
      @profile = appraisal_team.profile(@subject, viewer: current_user)
      @profile.record_view! unless read_only?
      @page_view = show_component
    end

    def draft
      @profile = appraisal_team.profile(@subject)
      OpenProject::LocaleHelper.with_locale_for(current_user) do
        Assistant::Appraisals::Narrative.new(@profile, author: current_user).save_draft!
      end
      respond(t("assistant.performance.announce.drafted"))
    rescue Assistant::Llm::NotConfigured
      respond(t("assistant.performance.errors.not_configured"), failed: true)
    rescue Assistant::Llm::OverBudget
      respond(t("assistant.performance.errors.over_budget"), failed: true)
    rescue Assistant::Llm::Error
      respond(t("assistant.performance.errors.unavailable"), failed: true)
    end

    def finalize
      appraisal = Assistant::Appraisal.where(project: @project, subject: @subject).find(params.expect(:appraisal_id))
      text = params[:narrative].to_s.strip.first(10_000)
      return respond(t("assistant.performance.errors.empty"), failed: true) if text.blank?

      appraisal.update!(narrative: text, author: current_user, finalized_at: Time.current)
      respond(t("assistant.performance.announce.finalized", name: @subject.name))
    end

    def note
      key = params[:metric_key].to_s
      key = "general" unless Assistant::Appraisals::Profile::DIMENSIONS.include?(key)
      note = Assistant::AppraisalNote.new(subject: @subject, project: @project, metric_key: key,
                                          note: params[:note].to_s.strip)
      return respond(note.errors.full_messages.to_sentence, failed: true) unless note.save

      respond(t("assistant.performance.announce.noted"))
    end

    private

    def find_subject
      @subject = Assistant::Proactive::Routing.people(@project).find { it.id == params[:user_id].to_i }
      @subject ||= User.find_by(id: params[:user_id]) if params[:user_id].to_i == current_user.id
      render_404 unless @subject
    end

    def may_view_others? = archived_for_admin? || (!read_only? && access.view_others?)

    def own? = @subject == current_user

    def authorize_view
      deny_access unless (@subject && own?) || may_view_others?
    end

    def authorize_note
      deny_access unless own?
    end

    def access = @access ||= Assistant::PerformanceAccess.new(@project, current_user)

    def period_key = PERIODS.key?(params[:period].to_s) ? params[:period].to_s : DEFAULT_PERIOD

    def appraisal_team
      @appraisal_team ||= Assistant::Appraisals::Team.new(project: @project, from: Date.current - PERIODS[period_key],
                                                          to: Date.current)
    end

    def show_component
      Assistant::AppraisalComponent.new(profile: @profile || appraisal_team.profile(@subject), viewer: current_user,
                                        period: period_key, periods: PERIODS.keys, may_view_others: may_view_others?,
                                        may_appraise: !read_only? && access.appraise?, read_only: read_only?)
    end

    def respond(message, failed: false)
      respond_to do |format|
        format.turbo_stream do
          streams = [live_region(message)]
          streams.unshift(turbo_stream.replace(Assistant::AppraisalComponent::ID, show_component, method: :morph)) unless failed
          streams << flash_stream(message) if failed
          render turbo_stream: streams, status: failed ? :unprocessable_entity : :ok
        end
        format.html do
          flash[failed ? :error : :notice] = message
          redirect_to project_member_performance_path(@project, @subject, period: period_key)
        end
      end
    end

    def flash_stream(message)
      OpPrimer::FlashComponent.new(scheme: :danger, icon: :stop).with_content(message)
                              .render_as_turbo_stream(view_context:, action: :flash)
    end
  end
end
