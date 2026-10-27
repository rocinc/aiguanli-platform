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
require_relative "../../support/intent_helpers"

# 04 D1 (three sentences for who missed it) and D6 (remind me).
RSpec.describe "Meetings and reminders" do # rubocop:disable RSpec/DescribeClass
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking meetings assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages view_meetings use_assistant]) }
  shared_let(:ada) { create(:user, firstname: "Ada", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:) }

  before { Assistant::Membership.ensure_member!(project) }

  describe Assistant::MissedMeeting do
    let(:meeting) { create(:meeting, project:, author: ada, start_time: 1.day.ago) }
    let(:llm) { instance_double(Assistant::Llm, json: { "summary" => "Export ships as CSV. Ben takes the import. Review on Friday." }) }

    before do
      allow(Assistant::Llm).to receive(:configured?).and_return(true)
      create(:meeting_participant, meeting:, user: ada, attended: true)
      create(:meeting_participant, meeting:, user: ben, attended: false)
      create_intent(project:, subject: meeting, owner: ben, kind: "commitment", status: "open", title: "Import",
                    quote: "Ben 接导入", stated_at: 1.day.ago)
    end

    it "tells only those who missed it, in three sentences, with what is now theirs" do
      described_class.new(meeting, llm:).call

      signal = Assistant::Signal.sole
      expect(signal).to have_attributes(recipient: ben, detector: "missed_meeting")
      expect(signal.because).to eq(["Export ships as CSV. Ben takes the import. Review on Friday.", "now yours: Import"])
      described_class.new(meeting, llm:).call
      expect(Assistant::Signal.count).to eq(1)
    end
  end

  describe Assistant::Actions::Steps::CreateReminder do
    it "sets the person's own reminder at once, in their name" do
      action = Assistant::Actions::Propose.call(
        kind: "reminder", title: "Remind me", on_behalf_of: ben, project:, subject: work_package,
        steps: [{ "op" => "create_reminder",
                  "attributes" => { "work_package_id" => work_package.id, "remind_at" => 3.days.from_now.iso8601, "note" => "看一下" } }]
      )

      expect(action.reload).to have_attributes(tier: "t1", status: "executed")
      expect(Reminder.sole).to have_attributes(creator: ben, remindable: work_package, note: "看一下")
    end
  end
end
