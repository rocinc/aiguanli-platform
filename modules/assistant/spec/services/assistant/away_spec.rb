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

RSpec.describe Assistant::Away do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role,
           permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:sam) { create(:user, firstname: "Sam", lastname: "S", member_with_roles: { project => role }) }
  shared_let(:quinn) { create(:user, firstname: "Quinn", lastname: "Q", member_with_roles: { project => role }) }

  # Monday 2026-09-28 back, after the week of 2026-09-21.
  let(:back) { Time.zone.local(2026, 9, 28, 9) }
  let(:left) { Date.new(2026, 9, 18) }
  let!(:ours) do
    travel_to(Time.zone.local(2026, 9, 1)) do
      create(:work_package, project:, assigned_to: ben, subject: "Search API", due_date: Date.new(2026, 9, 25))
    end
  end
  let!(:handed) do
    travel_to(Time.zone.local(2026, 9, 1)) do
      create(:work_package, project:, assigned_to: ben, subject: "UI wiring")
    end
  end

  def away(now: back) = described_class.new(user: ben, now:)

  def present_on(date)
    Assistant::Preference.for(ben).tap { it.presence = { "today" => date.iso8601 } }.save!
  end

  def change!(work_package, actor:, time:, **attributes)
    travel_to(time) do
      result = User.execute_as(actor) do
        WorkPackages::UpdateService.new(user: actor, model: work_package.reload).call(**attributes)
      end
      raise result.errors.full_messages.join(", ") unless result.success?
    end
  end

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
  end

  it "says nothing after a weekend" do
    present_on(Date.new(2026, 9, 25))
    described_class.mark_present!(ben, now: back)

    expect(away).not_to be_away
    expect(away.to_h).to eq({})
  end

  it "remembers the day before today only once a day" do
    present_on(left)
    described_class.mark_present!(ben, now: back)
    described_class.mark_present!(ben, now: back + 3.hours)

    expect(Assistant::Preference.for(ben).reload.presence).to include("today" => "2026-09-28", "before" => "2026-09-18")
  end

  context "when back after a week off" do
    before do
      present_on(left)
      change!(ours, actor: sam, time: Time.zone.local(2026, 9, 21, 10), due_date: Date.new(2026, 9, 30))
      change!(handed, actor: sam, time: Time.zone.local(2026, 9, 22, 11), assigned_to: quinn)
      described_class.mark_present!(ben, now: back)
    end

    it "tells how long and what others changed, with who did it" do
      data = away.to_h

      expect(data).to include("from" => "2026-09-19", "to" => "2026-09-27", "working_days" => 5)
      changed = data["changed"].sole
      expect(changed["headline"]).to include("##{ours.id}", "Sam S")
      expect(changed["because"].first).to include(Assistant::Text.day(Date.new(2026, 9, 30)))
      expect(changed.dig("subject", "id")).to eq(ours.id)
    end

    it "lists what was handed to someone else apart from other changes" do
      data = away.to_h

      reassigned = data["reassigned"].sole
      expect(reassigned.dig("subject", "id")).to eq(handed.id)
      expect(reassigned["because"]).to include(a_string_including("Quinn Q"))
      expect(data["changed"].map { it.dig("subject", "id") }).not_to include(handed.id)
    end

    it "leaves out what the person changed themselves" do
      change!(ours, actor: ben, time: Time.zone.local(2026, 9, 23, 9), subject: "Search API v2", due_date: Date.new(2026, 10, 2))

      expect(away.to_h["changed"].sole["headline"]).to include("Sam S")
      expect(away.to_h["changed"].sole["because"].join).not_to include("10/02")
    end

    it "lists the questions still waiting for an answer and how long they waited" do
      create_intent(project:, subject: ours, owner: sam, counterparty: ben, kind: "question", status: "open",
                    title: "Does export keep the watermark?", quote: "Does export keep the watermark?",
                    stated_at: Time.zone.local(2026, 9, 22, 10))

      asked = away.to_h["asked"].sole
      expect(asked["headline"]).to include("Sam S", "watermark")
      expect(asked["because"]).to eq(["waiting 4 working days"])
    end

    it "lists what was promised before today and leaves out what was written today" do
      create_intent(project:, subject: ours, owner: ben, counterparty: sam, said_due_on: Date.new(2026, 10, 2),
                    title: "Export before Friday", stated_at: Time.zone.local(2026, 9, 24, 10))
      create_intent(project:, subject: handed, owner: ben, counterparty: sam, said_due_on: Date.new(2026, 10, 2),
                    title: "Wire up the UI", stated_at: Time.zone.local(2026, 9, 28, 8))

      expect(away.to_h["promised"].map { it["headline"] }).to match([a_string_including("Export before Friday")])
    end

    it "shows up in the brief" do
      brief = Assistant::Brief.new(user: ben, now: back)

      expect(brief.away["changed"]).to be_present
    end

    it "stays out of the brief once the person has muted the rule" do
      Assistant::Preference.for(ben).mute!("away_digest")

      expect(Assistant::Brief.new(user: ben, now: back).away).to be_nil
    end

    it "stays for three working days after coming back and then goes" do
      described_class.mark_present!(ben, now: back + 1.day)
      expect(away(now: back + 1.day)).to be_away

      described_class.mark_present!(ben, now: back + 3.days)
      expect(away(now: back + 3.days)).to be_away

      described_class.mark_present!(ben, now: back + 4.days)
      expect(away(now: back + 4.days)).not_to be_away
    end
  end

  it "shows after the paused reminders end, and keeps showing for three working days" do
    present_on(Date.new(2026, 9, 28))
    ben.pref.update!(pause_reminders: { "enabled" => "1", "first_day" => "2026-09-29", "last_day" => "2026-10-02" })

    expect(away(now: Time.zone.local(2026, 10, 1, 9))).not_to be_away
    expect(away(now: Time.zone.local(2026, 10, 5, 9)).period)
      .to have_attributes(from: Date.new(2026, 9, 29), to: Date.new(2026, 10, 2))
    expect(away(now: Time.zone.local(2026, 10, 7, 9))).to be_away
    expect(away(now: Time.zone.local(2026, 10, 8, 9))).not_to be_away
  end

  it "counts recorded time off as away even when the gap is short" do
    present_on(Date.new(2026, 9, 23))
    UserNonWorkingTime.create!(user: ben, start_date: Date.new(2026, 9, 24), end_date: Date.new(2026, 9, 29))
    described_class.mark_present!(ben, now: Time.zone.local(2026, 9, 30, 9))

    expect(away(now: Time.zone.local(2026, 9, 30, 9)).period.working_days).to eq(4)
  end
end
