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
  # The proposals under one agenda item, as the frame the meeting page
  # reloads when the stream says new ones were made for this person.
  class SourceSignalsController < ApplicationController
    before_action :require_login
    before_action :find_agenda_item
    authorization_checked! :show

    def show
      render Assistant::SourceSignalsComponent.new(source: @agenda_item, user: current_user, frame: true), layout: false
    end

    private

    def find_agenda_item
      @agenda_item = MeetingAgendaItem.includes(meeting: :project).find_by(id: params.expect(:agenda_item_id))
      meeting = @agenda_item&.meeting
      return render_404 unless meeting&.visible?(current_user)

      head(:no_content) unless Assistant::Surface.available?(meeting.project, current_user)
    end
  end
end
