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

RSpec.describe Assistant::Actions::Steps::CreateMeetingAgendaItem do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking meetings assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages view_meetings manage_agendas edit_meetings use_assistant])
  end
  shared_let(:host) { create(:user, firstname: "Ada", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:) }
  shared_let(:meeting) { create(:meeting, project:, author: host, start_time: 2.days.from_now) }

  before { Assistant::Membership.ensure_member!(project) }

  def propose(on_behalf_of, **attributes)
    Assistant::Actions::Propose.call(
      kind: "agenda_draft", title: "Prepare the agenda", on_behalf_of:, project:, subject: meeting, auto_execute: false,
      steps: [{ op: "create_meeting_agenda_item", attributes: { meeting_id: meeting.id, title: "Last time we said", **attributes } }]
    )
  end

  it "adds the item to the last section, as a work package item when one is given, when the host confirms" do
    action = propose(host, work_package_id: work_package.id, notes: "- #{work_package.subject}", duration_in_minutes: 10)
    expect(action).to have_attributes(status: "proposed", tier: "t1")

    executed = Assistant::Actions::Execute.call(action, decided_by: host)
    expect(executed.reload).to have_attributes(status: "executed", error: nil)

    item = meeting.agenda_items.reload.last
    expect(item).to have_attributes(title: "Last time we said", item_type: "work_package", work_package_id: work_package.id,
                                    duration_in_minutes: 10, author: Assistant.user)
    expect(item.meeting_section).to eq(meeting.sections.order(:position).last)
    expect(meeting.agenda_items.count).to eq(1)
  end

  it "can be taken back, and the preview says what is added" do
    action = propose(host)
    expect(action.preview["changes"].sole).to include("kind" => "agenda_item", "created" => true)

    Assistant::Actions::Execute.call(action, decided_by: host)
    result = Assistant::Actions::Undo.call(action.reload, user: host)

    expect(result.success).to be(true)
    expect(meeting.agenda_items.reload).to be_empty
  end

  it "waits for the host when someone else's meeting gets the item, and nothing is written in preview" do
    expect(propose(ben)).to have_attributes(status: "proposed", tier: "t2")
    expect(propose(host, presenter_id: ben.id).tier).to eq("t2")
    expect(meeting.agenda_items.reload).to be_empty
  end

  it "keeps the planning section for decisions at the bottom when later items are added" do
    decisions = I18n.t("assistant.proactive.sprint_planning_prep.sections.decisions")
    Assistant::Actions::Execute.call(propose(host, title: decisions), decided_by: host)
    Assistant::Actions::Execute.call(propose(host, title: "Pre-mortem"), decided_by: host)

    expect(meeting.agenda_items.reload.map(&:title)).to eq(["Pre-mortem", decisions])
  end
end
