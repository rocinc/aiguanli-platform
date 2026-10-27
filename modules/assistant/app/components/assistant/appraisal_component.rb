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
  # One member's page. The member and whoever appraises them see the same
  # numbers, the same basis, the same notes and the same final appraisal;
  # the member also sees who looked, and can add their side to any line.
  # A draft stays with the appraisers until it is final; the member is told
  # one is being written.
  class AppraisalComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers
    include AppraisalFormatting

    ID = "assistant-appraisal-page"
    VIEWS_SHOWN = 12

    def initialize(profile:, viewer:, period:, periods:, may_view_others:, may_appraise:, read_only: false)
      super()
      @profile = profile
      @viewer = viewer
      @period = period
      @periods = periods
      @may_view_others = may_view_others
      @may_appraise = may_appraise
      @read_only = read_only
    end

    attr_reader :profile, :viewer, :period, :periods

    delegate :user, :project, to: :profile

    def data = @data ||= profile.to_h

    def own? = viewer == user

    def may_view_others? = @may_view_others

    def may_appraise? = @may_appraise && !own? && !read_only?

    def may_note? = own? && !read_only?

    def read_only? = @read_only

    def dimensions = Assistant::Appraisals::Profile::DIMENSIONS

    def dim(key) = data.dig("dimensions", key) || {}

    def evidence(key) = Array(dim(key)["evidence"])

    def notes(key) = Array(dim(key)["notes"])

    def general_notes = Array(data["general_notes"])

    def note_day(note) = Assistant::Text.day(Date.iso8601(note["on"]))

    def trend_text(key) = trend_line(dim(key), period)

    def dom_id(key) = "assistant-appraisal-#{key}"

    def situation = data["situation"].to_h

    def situation_items
      items = []
      if situation["absent_days"].to_i.positive?
        items << t("assistant.performance.situation.absent",
                   count: situation["absent_days"])
      end
      if situation["blocked_working_days"].to_i.positive?
        items << t("assistant.performance.situation.blocked_long", count: situation["blocked_working_days"])
      end
      Array(situation["firefighting"]).each { items << t("assistant.performance.situation.firefight_item", ref: it) }
      if situation["renegotiated_early"].to_i.positive?
        items << t("assistant.performance.situation.renegotiated", count: situation["renegotiated_early"])
      end
      items
    end

    def appraisals
      @appraisals ||= Assistant::Appraisal.where(project:, subject: user).includes(:author).order(created_at: :desc).to_a
    end

    def final = appraisals.find(&:finalized?)

    def draft = appraisals.find { !it.finalized? && (final.nil? || it.created_at > final.finalized_at) }

    def view_scope = Assistant::AppraisalView.within_window.where(project:, subject: user).includes(:viewer)

    def views = @views ||= view_scope.limit(VIEWS_SHOWN).to_a

    def views_summary = @views_summary ||= views_line(view_scope.to_a)

    def view_line(view)
      t("assistant.performance.viewed", name: view.viewer.name, date: Assistant::Text.moment(view.created_at))
    end

    def heading
      own? ? t("assistant.performance.own_title") : t("assistant.performance.member_title", name: user.name)
    end

    def period_path(key) = url_helpers.project_member_performance_path(project, user, period: key)

    def team_path = url_helpers.project_performance_team_path(project, period:)

    def note_path = url_helpers.project_member_performance_notes_path(project, user, period:)

    def draft_path = url_helpers.project_draft_member_performance_path(project, user, period:)

    def finalize_path = url_helpers.project_finalize_member_performance_path(project, user, period:)

    def format_markdown(text) = helpers.format_text(text.to_s, project:, only_path: true)

    delegate :configured?, to: :"Assistant::Llm"
  end
end
