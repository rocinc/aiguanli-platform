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
  # The empty drawer every page carries. It fills itself from the panel
  # endpoint when opened, with whatever object the page is about.
  class PanelDialogComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    DIALOG_ID = "assistant-panel-dialog"
    FRAME_ID = "assistant-panel-frame"

    BEACON_TYPES = { WorkPackage => "work_package", Meeting => "meeting", ::Message => "message",
                     WikiPage => "wiki_page", News => "news", Version => "version", Project => "project" }.freeze

    def initialize(user:, context: nil, viewed: nil)
      super()
      @user = user
      @context = context
      @viewed = viewed
    end

    attr_reader :user, :context, :viewed

    def render? = user.logged? && !user.is_a?(AssistantUser) && Assistant::PanelDialogComponent.anywhere?(user)

    def self.anywhere?(user)
      RequestStore.fetch([:assistant_anywhere, user.id]) do
        user.admin? || user.allowed_in_any_project?(:use_assistant)
      end
    end

    def assistant_user_id = AssistantUser.instance.id

    def shortcuts? = !user.pref.disable_keyboard_shortcuts?

    def src = url_helpers.assistant_panel_path(context: context&.to_gid&.to_s)

    def title = t("assistant.panel.title", name: AssistantUser.instance.name)

    def beacon_type = viewed && BEACON_TYPES.find { |model, _| viewed.is_a?(model) }&.last

    def beacon_url = url_helpers.assistant_views_path
  end
end
