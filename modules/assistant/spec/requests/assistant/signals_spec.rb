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

RSpec.describe "What a person says back to a notice", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role,
           permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant manage_assistant])
  end
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:lead) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) do
    create(:work_package, project:, assigned_to: sam, due_date: Date.new(2026, 10, 13))
  end

  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:signal) do
    Assistant::Signal.create!(detector: "stalled", fingerprint: "s", recipient: sam, project:, subject: work_package, channel: "brief",
                              state: "delivered", deliver_at: Time.current, delivered_at: Time.current,
                              payload: { "headline" => "Stalled", "because" => ["x"], "options" => [],
                                         "facts" => { "due_date" => "2026-10-10" } })
  end

  before do
    Assistant::Membership.ensure_member!(project)
    Assistant::Proactive::ProjectSettings.write!(project, lead_ids: [lead.id])
    login_as(sam)
  end

  def reply_text = Capybara.string(response.body.scan(%r{<template>(.*?)</template>}m).flatten.join).text

  it "answers 'wrong' with an apology, counts a false alarm and says what changed" do
    patch assistant_signal_path(signal), params: { outcome: "wrong" }, headers: turbo

    expect(signal.reload.outcome).to eq("wrong")
    expect(reply_text).to include(I18n.t("assistant.notice.replies.wrong"))
    expect(Assistant::Proactive::Feedback.false_alarms(project)).to eq("stalled" => 1)
  end

  it "keeps leaving it, declining and taking back apart from 'wrong'" do
    patch assistant_signal_path(signal), params: { outcome: "rejected" }, headers: turbo

    expect(signal.reload.outcome).to eq("rejected")
    expect(Assistant::Proactive::Feedback.false_alarms(project)).to be_empty
  end

  it "never asks again about the same kind on the same object after 'I know already'" do
    patch assistant_signal_path(signal), params: { outcome: "known" }, headers: turbo
    signal.update_columns(created_at: 10.days.ago)
    candidate = Assistant::Proactive::Candidate.build(detector: "stalled", fingerprint: "other", recipient: sam,
                                                      subject: work_package, project:)

    verdict = Assistant::Proactive::Gate.new(candidate, preference: Assistant::Preference.effective(sam, project)).call

    expect(verdict.reasons).to include("already_known")
  end

  it "passes 'not mine' on to the next in line" do
    patch assistant_signal_path(signal), params: { outcome: "not_mine" }, headers: turbo

    expect(signal.reload.outcome).to eq("not_mine")
    expect(Assistant::Signal.where(recipient: lead, detector: "stalled").count).to eq(1)
  end

  it "asks when to come back after 'bad timing' and remembers it once chosen" do
    patch assistant_signal_path(signal), params: { outcome: "bad_timing", density: "card" }, headers: turbo
    expect(signal.reload.outcome).to be_nil
    expect(reply_text).to include(I18n.t("assistant.notice.replies.timing"))

    patch assistant_signal_path(signal), params: { outcome: "snoozed", until: "tomorrow", reason: "bad_timing" }, headers: turbo

    expect(signal.reload).to have_attributes(state: "held")
    expect(signal.payload["bad_timing"]).to eq(1)
  end

  it "mutes a kind in one project only" do
    patch assistant_signal_path(signal), params: { outcome: "muted", scope: "project" }, headers: turbo

    expect(Assistant::Preference.effective(sam, project).muted?("stalled")).to be(true)
    expect(Assistant::Preference.effective(sam, create(:project)).muted?("stalled")).to be(false)
    expect(reply_text).to include("no longer tell you", "turn it back on in the assistant settings")
  end

  it "replaces every copy of the notice at once" do
    patch assistant_signal_path(signal), params: { outcome: "rejected" }, headers: turbo

    %w[line card].each do |density|
      expect(response.body).to include("data-assistant-density=&#39;#{density}&#39;")
    end
  end

  describe "taking back what was done on a grant" do
    let(:action) do
      Assistant::Actions::Propose.call(
        kind: "reschedule", title: "Move it", on_behalf_of: sam, project:, subject: work_package, basis: [],
        steps: [{ op: "update_work_package", type: "WorkPackage", id: work_package.id, attributes: { due_date: "2026-10-16" } }],
        auto_execute: false
      ).tap do |it|
        it.update_columns(tier: "t1")
        Assistant::Actions::Execute.call(it, decided_by: sam)
      end
    end

    before { Assistant::Grant.create!(project:, action_kind: "reschedule", granted_by: sam) }

    it "asks once, and a yes takes the grant back" do
      post undo_assistant_action_path(action), headers: turbo
      expect(reply_text).to include(I18n.t("assistant.notice.handover.ask"))

      post undo_assistant_action_path(action), headers: turbo
      expect(reply_text).not_to include(I18n.t("assistant.notice.handover.ask"))

      post handover_assistant_action_path(action), params: { answer: "yes" }, headers: turbo

      expect(Assistant::Grant.live.where(project:, action_kind: "reschedule")).to be_empty
    end
  end

  describe "taking back a date it recorded from the person's own words" do
    def record_promise(due)
      item = create_intent(project:, subject: work_package, owner: sam, said_due_on: due, quote: "Done by then")
      Assistant::Understanding::Promises.for([item]).sole
    end

    it "asks once, and a yes makes it ask before recording the next one" do
      action = record_promise(Date.new(2026, 10, 12))
      expect(action).to be_executed
      expect(work_package.reload.due_date).to eq(Date.new(2026, 10, 12))

      post undo_assistant_action_path(action), headers: turbo
      expect(reply_text).to include(I18n.t("assistant.notice.handover.ask"))
      expect(work_package.reload.due_date).to eq(Date.new(2026, 10, 13))

      post handover_assistant_action_path(action), params: { answer: "yes" }, headers: turbo
      expect(Assistant::Preference.for(sam)).to be_asks_first("promise_date")

      asked = record_promise(Date.new(2026, 10, 9))
      expect(asked).to be_proposed
      expect(Assistant::Signal.where(detector: "said_promise", action: asked, recipient: sam, channel: "inline")).to exist
      expect(work_package.reload.due_date).to eq(Date.new(2026, 10, 13))
    end

    it "lets an exception pass: a no keeps recording by itself" do
      action = record_promise(Date.new(2026, 10, 12))
      post undo_assistant_action_path(action), headers: turbo
      post handover_assistant_action_path(action), params: { answer: "no" }, headers: turbo

      expect(Assistant::Preference.for(sam)).not_to be_asks_first("promise_date")
      expect(record_promise(Date.new(2026, 10, 9))).to be_executed
    end
  end
end
