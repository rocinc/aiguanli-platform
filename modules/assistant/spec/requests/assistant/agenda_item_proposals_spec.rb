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
require "spec_helper"

RSpec.describe "The proposals under a meeting agenda item", type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking meetings assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages view_meetings use_assistant])
  end
  shared_let(:host) { create(:user, member_with_roles: { project => role }) }
  shared_let(:other) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:) }
  shared_let(:meeting) { create(:meeting, project:, author: host) }
  shared_let(:agenda_item) { create(:meeting_agenda_item, meeting:, author: host, work_package:, item_type: :work_package) }

  let(:frame_id) { "assistant-proposals-meeting-agenda-item-#{agenda_item.id}" }

  before do
    Assistant::Signal.create!(detector: "said_change", fingerprint: "a", recipient: host, project:, subject: meeting,
                              channel: "inline", deliver_at: Time.current,
                              payload: { "headline" => "Move the due date", "source_gid" => agenda_item.to_gid.to_s })
  end

  it "answers the frame with the host's cards" do
    login_as(host)
    get assistant_agenda_item_proposals_path(agenda_item)

    expect(response.body).to include(%(<turbo-frame id="#{frame_id}">))
    expect(response.body).to include("Move the due date")
  end

  it "answers an empty frame to anyone else" do
    login_as(other)
    get assistant_agenda_item_proposals_path(agenda_item)

    expect(response.body).to eq(%(<turbo-frame id="#{frame_id}"></turbo-frame>))
  end

  it "is not found for someone who cannot see the meeting" do
    login_as(create(:user))
    get assistant_agenda_item_proposals_path(agenda_item)

    expect(response).to have_http_status(:not_found)
  end

  it "broadcasts only a frame to reload, to the person the cards are for" do
    stream = Assistant::SourceSignalsComponent.stream_for(meeting, host)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    Assistant::SourceSignalsComponent.broadcast_reload(agenda_item, [host, host])

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).once
      .with(stream, target: frame_id, html: include(%(src="/assistant/agenda_items/#{agenda_item.id}/proposals")))
  end
end
