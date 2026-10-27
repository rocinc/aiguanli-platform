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
  # One section per project: the person's own numbers in short, whether a
  # written appraisal is final, and who looked. The full page is one click on.
  class MyPerformanceComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers
    include AppraisalFormatting

    PERIOD = Assistant::PerformanceController::DEFAULT_PERIOD

    def initialize(user:, projects:)
      super()
      @user = user
      @projects = projects
    end

    attr_reader :user, :projects

    def sections
      @sections ||= projects.map do |project|
        to = Date.current
        profile = Assistant::Appraisals::Profile.new(
          Assistant::Appraisals::MemberFacts.new(user:, project:, from: to - PERIOD.to_i, to:)
        )
        { project:, data: profile.to_h, final: final_for(project), views_line: views_line(views_for(project)) }
      end
    end

    def dimensions = Assistant::Appraisals::Profile::DIMENSIONS

    def dim(section, key) = section[:data].dig("dimensions", key) || {}

    def notes_count(section)
      section[:data]["dimensions"].to_h.values.sum { Array(it["notes"]).size } + Array(section[:data]["general_notes"]).size
    end

    def final_line(section)
      final = section[:final]
      return unless final

      t("assistant.performance.mine.final", name: final.author&.name || t("assistant.timeline.someone"),
                                            date: Assistant::Text.day(final.finalized_at))
    end

    def page_path(project) = url_helpers.project_member_performance_path(project, user, period: PERIOD)

    private

    def final_for(project)
      Assistant::Appraisal.finalized.where(project:, subject: user).includes(:author).order(finalized_at: :desc).first
    end

    def views_for(project)
      Assistant::AppraisalView.within_window.where(project:, subject: user).includes(:viewer).to_a
    end
  end
end
