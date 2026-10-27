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
  # "Say something" under a notice, a draft or a receipt: opens the panel on
  # that one thing, so it can be asked about where it stands.
  class SayButtonComponent < ApplicationComponent
    def initialize(record:, user:, describedby: nil, menu: false)
      super()
      @record = record
      @user = user
      @describedby = describedby
      @menu = menu
    end

    attr_reader :record, :user, :describedby, :menu

    def render?
      user.logged? && !user.is_a?(AssistantUser) && about&.visible_to?(user) && Assistant::PanelDialogComponent.anywhere?(user)
    end

    def call
      render(Primer::Beta::Button.new(type: :button, size: :small, scheme: :invisible, title: t("assistant.thread.say_hint"),
                                      "aria-describedby": describedby, role: (:menuitem if menu),
                                      data: { assistant_panel_open: true, assistant_context: record.to_gid.to_s,
                                              assistant_pin: true, test_selector: "assistant-say",
                                              action: ("click->assistant--verbs#closeMenu" if menu) }.compact)) do
        t("assistant.thread.say")
      end
    end

    private

    def about = @about ||= Assistant::Conversations::Context.for(record)
  end
end
