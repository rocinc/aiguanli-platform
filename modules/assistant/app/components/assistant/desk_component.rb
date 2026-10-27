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
  class DeskComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    TABS = %w[watching duties ideas insights].freeze
    INTRO_KEYS = { "duties" => "assistant.duties_page.description" }.freeze

    def initialize(project:, user:, tab:, tabs:, read_only: false)
      super()
      @project = project
      @user = user
      @tab = tab
      @tabs = tabs
      @read_only = read_only
    end

    attr_reader :project, :user, :tab, :tabs

    def read_only? = @read_only

    def duty_count = Assistant::Duty.where(project:).count

    def level_text = t("assistant.desk.levels.#{preference.level}")

    def summary = t("assistant.desk.summary", count: duty_count, level: level_text)

    def paused_until = @paused_until ||= Assistant::Preference.find_by(owner: user)&.then { it.paused_until if it.paused? }

    def paused_text
      t("assistant.desk.paused", day: Assistant::Text.day(paused_until.in_time_zone(user.time_zone || Time.zone).to_date))
    end

    def tab_label(key) = t("assistant.desk.tabs.#{key}")

    def intro = (t(INTRO_KEYS[tab]) if INTRO_KEYS.key?(tab))

    def tab_content
      case tab
      when "watching" then Assistant::Desk::WatchingComponent.new(project:, user:)
      when "duties" then Assistant::DutiesPageComponent.new(project:, user:, read_only: read_only?)
      when "ideas" then Assistant::Desk::IdeasComponent.new(project:, user:, read_only: read_only?)
      when "insights" then Assistant::Desk::InsightsComponent.new(project:, user:)
      end
    end

    private

    def preference = @preference ||= Assistant::Preference.effective(user, project)
  end
end
