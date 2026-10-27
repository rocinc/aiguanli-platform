# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"
RSpec.describe Assistant::Actions::Steps::CreateMeetingOutcome do
  shared_let(:project) { create(:project, enabled_module_names: %w[meetings assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_meetings manage_agendas manage_outcomes edit_meetings use_assistant])
  end
  shared_let(:host) { create(:user, firstname: "Ada", member_with_roles: { project => role }) }

  let(:meeting) { create(:meeting, project:, author: host, start_time: 1.hour.ago, state: :in_progress) }
  let(:item) { create(:meeting_agenda_item, meeting:, title: "Release date") }

  before { Assistant::Membership.ensure_member!(project) }

  def propose(agenda_item)
    Assistant::Actions::Propose.call(
      kind: "meeting_outcome", title: "Record the decision", on_behalf_of: host, project:, subject: agenda_item.meeting,
      auto_execute: false,
      steps: [{ op: "create_meeting_outcome", attributes: { agenda_item_id: agenda_item.id, kind: "decision", notes: "Ship A." } }]
    )
  end

  it "records the outcome in the platform's way, says it in one line, and can be taken back" do
    action = propose(item)

    expect(action.preview["changes"].sole).to include("kind" => "meeting_outcome", "label" => "Release date")
    Assistant::Actions::Execute.call(action, decided_by: host)
    expect(action.reload.status).to eq("executed")
    expect(item.reload.outcomes.sole).to have_attributes(notes: "Ship A.", author: Assistant.user)

    expect(Assistant::Actions::Undo.call(action, user: host).success).to be(true)
    expect(item.reload.outcomes).to be_empty
  end

  it "says why when the meeting is not running" do
    closed = create(:meeting_agenda_item, meeting: create(:meeting, project:, author: host, start_time: 2.days.from_now))

    expect(propose(closed).preview["errors"]).to eq([I18n.t("assistant.actions.errors.meeting_not_running")])
  end
end
