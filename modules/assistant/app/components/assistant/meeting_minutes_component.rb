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
  # After a meeting closes with nothing written down (S6.3): the minutes the
  # assistant drafted, for the host to read and send, or the line saying they
  # were sent. The draft lands in the meeting's own wiki page, so it is shown
  # here, at the top of the meeting, as the card it is (L2.2).
  class MeetingMinutesComponent < ApplicationComponent
    SENT_LINGERS = 3.days

    def initialize(meeting:, user:)
      super()
      @meeting = meeting
      @user = user
    end

    attr_reader :meeting, :user

    def action
      return @action if defined?(@action)

      @action = meeting.closed? ? latest : nil
    end

    def render? = action.present? && Assistant::Surface.available?(meeting.project, user)

    def call
      content_tag(:div, render(Assistant::DraftComponent.new(action:, user:, heading_level: 3)), class: "assistant-recap--minutes",
                                                                                                data: { test_selector: "assistant-meeting-minutes" })
    end

    private

    def latest
      actions = Assistant::Action.where(kind: "meeting_minutes", subject: meeting, on_behalf_of: user).order(created_at: :desc).to_a
      actions.detect { Assistant::Drafts.draft?(it, user) } ||
        actions.detect { it.executed? && it.updated_at > SENT_LINGERS.ago }
    end
  end
end
