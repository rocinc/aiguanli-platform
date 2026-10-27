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
  # Everyone in the project over one period, one row each. Sorting by a
  # dimension ranks only those with enough data; the rest follow, marked.
  class AppraisalsTeamComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers
    include AppraisalFormatting

    COLUMNS = %w[delivery estimation output quality collaboration word knowledge load].freeze

    def initialize(team:, user:, period:, periods:, sort: nil)
      super()
      @team = team
      @user = user
      @period = period
      @periods = periods
      @sort = COLUMNS.include?(sort.to_s) ? sort.to_s : nil
    end

    attr_reader :team, :user, :period, :periods, :sort

    delegate :project, to: :team

    def rows
      @rows ||= team.profiles.map { [it, it.to_h] }
    end

    def sorted_rows
      return rows.sort_by { |profile, _| profile.user.name } unless sort

      ranked, unranked = rows.partition { |profile, _| profile.value(sort) }
      lower_first = Assistant::Appraisals::Team::LOWER_IS_BETTER.include?(sort)
      ranked.sort_by { |profile, _| lower_first ? profile.value(sort) : -profile.value(sort) } +
        unranked.sort_by { |profile, _| profile.user.name }
    end

    def dim(hash, key) = hash.dig("dimensions", key) || {}

    def sort_path(key) = url_helpers.project_performance_team_path(project, period:, sort: key)

    def period_path(key) = url_helpers.project_performance_team_path(project, period: key, sort:)

    def member_path(member) = url_helpers.project_member_performance_path(project, member, period:)

    def aria_sort(key) = key == sort ? "descending" : nil

    def situation_line(hash)
      situation = hash["situation"].to_h
      parts = []
      if situation["absent_days"].to_i.positive?
        parts << t("assistant.performance.situation.absent",
                   count: situation["absent_days"])
      end
      if situation["blocked_working_days"].to_i.positive?
        parts << t("assistant.performance.situation.blocked", count: situation["blocked_working_days"])
      end
      if Array(situation["firefighting"]).any?
        parts << t("assistant.performance.situation.firefight",
                   count: Array(situation["firefighting"]).size)
      end
      parts.join(t("assistant.card.separator"))
    end

    def notes_count(hash)
      hash["dimensions"].to_h.values.sum { Array(it["notes"]).size } + Array(hash["general_notes"]).size
    end

    def finalized_for
      @finalized_for ||= Assistant::Appraisal.finalized.where(project:).group(:subject_id).maximum(:finalized_at)
    end

    # A dash reads as nothing, or as "dash"; the words are there for screen readers.
    def no_value
      helpers.safe_join([helpers.content_tag(:span, "–", "aria-hidden": true),
                         helpers.content_tag(:span, t("assistant.common.no_value"), class: "sr-only")])
    end
  end
end
