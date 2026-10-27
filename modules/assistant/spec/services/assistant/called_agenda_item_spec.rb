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

require "rails_helper"

RSpec.describe "Called from an agenda item's notes" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant meetings]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages use_assistant view_meetings edit_meetings manage_agendas]) }
  shared_let(:ada) { create(:user, member_with_roles: { project => role }) }
  shared_let(:meeting) { create(:meeting, project:, author: ada) }

  let(:mention) { Assistant::Reasoning::StepBuilder.mention(Assistant.user) }
  let(:agenda_item) { create(:meeting_agenda_item, meeting:, author: ada, notes: "Plain notes") }

  before do
    Assistant::Membership.ensure_member!(project)
    allow(Assistant::Reasoning::Agent).to receive(:new).and_return(
      instance_double(Assistant::Reasoning::Agent,
                      run: Assistant::Reasoning::Agent::Result.new(content: "We chose PDF first.\n\n- see #1", cards: [], rounds: 1,
                                                                 tool_calls: []))
    )
    User.current = ada
  end

  it "holds a line under the item, then turns it into the answer with the rest folded away" do
    agenda_item.update!(notes: "#{mention} what did we decide?")

    expect { Assistant::Events::Dispatch.agenda_item_written(agenda_item) }
      .to have_enqueued_job(Assistant::MentionJob).with(agenda_item, ada)
    held = Assistant::Signal.find_by(detector: "mention_answer", recipient: ada)
    expect(held.payload).to include("holding" => true, "source_gid" => agenda_item.to_gid.to_s)

    Assistant::Called::Mention.new(agenda_item, asker: ada).call

    expect(Assistant::Signal.where(detector: "mention_answer", recipient: ada).count).to eq(1)
    expect(held.reload.payload).to include("headline" => "We chose PDF first.", "answer" => a_string_including("see #1"))
    expect(held.payload).not_to have_key("holding")
  end

  it "does not call again for notes that already mentioned it" do
    agenda_item.update_columns(notes: "#{mention} first")
    agenda_item.update!(notes: "#{mention} first, edited")

    expect { Assistant::Events::Dispatch.agenda_item_written(agenda_item) }.not_to have_enqueued_job(Assistant::MentionJob)
  end

  describe "a conclusion that mentions it" do
    let(:outcome) { create(:meeting_outcome, meeting_agenda_item: agenda_item, kind: "decision", notes: "Plain decision", author: ada) }

    it "holds a line under the item and asks with the conclusion's words" do
      outcome.update!(notes: "#{mention} is this final?")

      expect { Assistant::Events::Dispatch.outcome_written(outcome) }
        .to have_enqueued_job(Assistant::MentionJob).with(agenda_item, ada)
      held = Assistant::Signal.find_by(detector: "mention_answer", recipient: ada)
      expect(held.payload).to include("holding" => true, "source_gid" => agenda_item.to_gid.to_s)

      Assistant::Called::Mention.new(agenda_item, asker: ada).call

      expect(held.reload.payload).to include("headline" => "We chose PDF first.")
      expect(Assistant::Signal.where(detector: "mention_answer", recipient: ada).count).to eq(1)
      expect(Assistant::Conversation.last.messages.first.content).to include("is this final?")
    end

    it "does not call again for a conclusion that already mentioned it" do
      outcome.update_columns(notes: "#{mention} first")
      outcome.update!(notes: "#{mention} first, edited")

      expect { Assistant::Events::Dispatch.outcome_written(outcome) }.not_to have_enqueued_job(Assistant::MentionJob)
    end
  end
end
