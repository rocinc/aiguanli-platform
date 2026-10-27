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
  class TopMenuButtonComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    def initialize(user:)
      super()
      @user = user
    end

    def render? = @user.logged? && Assistant::PanelDialogComponent.anywhere?(@user)

    def call
      content_tag(:div, class: "op-app-menu--item assistant-top-menu", data: { test_selector: "assistant-top-menu" }) do
        render(Primer::Beta::IconButton.new(icon: :"sparkle-fill", scheme: :invisible,
                                            classes: "op-app-header--primer-button",
                                            aria: { label: label, keyshortcuts: "a" },
                                            tooltip_direction: :sw,
                                            data: { show_dialog_id: Assistant::PanelDialogComponent::DIALOG_ID,
                                                    test_selector: "assistant-top-menu-button" }))
      end
    end

    private

    def label = t("assistant.panel.open", name: AssistantUser.instance.name, shortcut: "a")
  end
end
