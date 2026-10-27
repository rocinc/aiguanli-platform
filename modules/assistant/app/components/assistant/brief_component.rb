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
  # "Today" (H1): a note from a colleague at the start of the day. Fixed
  # groups in a fixed order; a group with nothing in it is not drawn.
  class BriefComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    AWAY_GROUPS = %w[asked reassigned changed promised].freeze

    def initialize(brief:, user:, project: nil)
      super()
      @brief = brief
      @user = user
      @project = project
    end

    attr_reader :brief, :user, :project

    delegate :decision_lines, :handled, :drafts, :done, :deferred, :away, :empty?, :newcomer?, to: :brief

    def title = t("assistant.brief.heading", day: brief.day)

    def quiet_text = newcomer? ? t("assistant.brief.newcomer") : t("assistant.brief.quiet")

    def project_name(entry)
      record = entry.is_a?(Assistant::Drafts::Item) ? entry.action : entry
      record.project&.name if brief.multiple_projects?
    end

    def away_range
      from = Date.iso8601(away["from"])
      to = Date.iso8601(away["to"])
      from += 1 until Assistant::Facts.working_day?(from) || from >= to
      to -= 1 until Assistant::Facts.working_day?(to) || to <= from
      t("assistant.away.range", from: Assistant::Text.day(from), to: Assistant::Text.day(to), count: away["working_days"])
    end

    def away_lines = AWAY_GROUPS.flat_map { Array(away[it]) }

    def away_project(line) = (line.dig("subject", "project") if brief.multiple_projects?)

    def away_because(line) = Array(line["because"]).first

    def deferred_title = t("assistant.brief.deferred", count: deferred.size)
  end
end
