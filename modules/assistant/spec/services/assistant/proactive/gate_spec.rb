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

RSpec.describe "The value gate" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:ben) { create(:user, member_with_roles: { project => role }) }
  shared_let(:lead) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: ben) }

  let(:now) { Time.zone.local(2026, 10, 13, 10) }
  let(:silent_writer) { Struct.new(:candidate, :options) { def call = {} } }

  def candidate(fingerprint: "1", detector: "stalled", channel: nil, impact: { critical_path: true, deadline: true })
    Assistant::Proactive::Candidate.build(detector:, fingerprint:, recipient: ben, subject: work_package, project:,
                                          nature: :own, impact:, channel:, headline: "Stalled")
  end

  def gate(c) = Assistant::Proactive::Gate.new(c, today: now.to_date).call

  def said!(fingerprint:, at:, detector: "stalled", payload: {})
    Assistant::Signal.create!(detector:, fingerprint:, recipient: ben, project:, subject: work_package, channel: "notification",
                              state: "delivered", deliver_at: at, delivered_at: at, created_at: at, payload:)
  end

  around { |example| travel_to(now) { example.run } }

  before { Member.where(principal: Assistant.user).update_all(created_at: 1.year.ago) }

  it "tells the same person about the same thing at most once a week, in whatever words" do
    said!(fingerprint: "old", at: now - 3.days)

    expect(gate(candidate(fingerprint: "new"))).to have_attributes(pass: false, reasons: ["already_said"])

    Assistant::Signal.update_all(created_at: now - 8.days)
    expect(gate(candidate(fingerprint: "new")).interrupt?).to be(true)
  end

  it "does not interrupt again about something that already went to the brief instead" do
    said!(fingerprint: "old", at: now - 10.days, payload: { "demoted" => "over_budget" })

    expect(gate(candidate(fingerprint: "new"))).to have_attributes(route: :brief, reasons: ["demoted_before"])
  end

  it "never lets the cap adapted on its own go above the level" do
    Assistant::Preference.for(ben).update!(proactivity: "active", interrupt_cap: 9)

    expect(Assistant::Preference.effective(ben, project).cap).to eq(4)
  end

  it "uses the number a person chose, above or below their level" do
    preference = Assistant::Preference.for(ben)
    preference.proactivity = "standard"
    preference.choose_cap(6)
    preference.save!
    expect(Assistant::Preference.effective(ben, project).cap).to eq(6)

    preference.choose_cap(1)
    preference.save!
    expect(Assistant::Preference.effective(ben, project).cap).to eq(1)
  end

  it "lets the cap of a level be lowered" do
    Assistant::Preference.for(ben).update!(proactivity: "active", interrupt_cap: 1)

    expect(Assistant::Preference.effective(ben, project).cap).to eq(1)
  end

  it "moves the fourth interruption of the day to the brief and marks it" do
    allow_any_instance_of(Assistant::Proactive::Timing).to receive(:working_now?).and_return(true)
    Assistant::Preference.for(ben).update!(proactivity: "active", interrupt_cap: 3)
    3.times { |i| said!(fingerprint: "x#{i}", detector: "critical_slip", at: now - 1.hour) }

    signal = Assistant::Proactive::Engine.new(project, now:, today: now.to_date, writer: silent_writer).consider(candidate)

    expect(signal).to have_attributes(channel: "brief")
    expect(signal.payload["demoted"]).to eq("over_budget")
  end

  it "lowers the cap for someone who lets interruptions pass, and never raises it again" do
    Assistant::Preference.for(ben).update!(proactivity: "active")
    6.times { |i| said!(fingerprint: "i#{i}", detector: "critical_slip", at: now - (i + 1).days) }
    Assistant::Signal.update_all(outcome: "ignored", outcome_at: now)

    Assistant::Proactive::Feedback.tune!(ben, "critical_slip")
    expect(Assistant::Preference.effective(ben, project).cap).to eq(3)

    Assistant::Signal.update_all(outcome: "adopted")
    Assistant::Proactive::Feedback.tune!(ben, "critical_slip")
    expect(Assistant::Preference.effective(ben, project).cap).to eq(3)
  end

  it "sends a rule the whole project ignores to the brief, once ten notices say so" do
    settle = lambda do |count|
      count.times do |i|
        Assistant::Signal.create!(detector: "stalled", fingerprint: "r#{count}#{i}", recipient: lead, project:,
                                  channel: "brief", state: "dismissed", deliver_at: now, outcome: "rejected", outcome_at: now)
      end
    end
    settle.call(9)
    expect(Assistant::Proactive::Feedback.demoted_detectors(project)).to be_empty

    settle.call(1)
    expect(Assistant::Proactive::Feedback.demoted_detectors(project)).to eq(["stalled"])

    allow_any_instance_of(Assistant::Proactive::Timing).to receive(:working_now?).and_return(true)
    signal = Assistant::Proactive::Engine.new(project, now:, today: now.to_date,
                                                       writer: silent_writer).consider(candidate(fingerprint: "fresh"))

    expect(signal).to have_attributes(channel: "brief")
    expect(signal.payload["demoted"]).to eq("demoted")
  end

  describe "when the notice was switched off" do
    def consider = Assistant::Proactive::Engine.new(project, now:, today: now.to_date, writer: silent_writer).consider(candidate)

    it "creates nothing for a rule the person muted, everywhere or in this project, or the project turned off" do
      switches = {
        "everywhere" => -> { Assistant::Preference.for(ben).mute!("stalled") },
        "in this project" => -> { Assistant::Preference.for(ben).mute_in!("stalled", project) },
        "for the project" => -> { Assistant::Proactive::ProjectSettings.write!(project, enabled: Assistant::Proactive::Catalog.keys - %w[stalled]) }
      }
      switches.each_value do |switch|
        switch.call

        expect { consider }.not_to change(Assistant::Signal, :count)
        expect(consider).to be_nil
        Assistant::Preference.delete_all
      end

      expect(consider).to be_a(Assistant::Signal)
    end
  end
end

RSpec.describe Assistant::Proactive::ProjectSettings do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:lead) { create(:user) }

  it "keeps rule switches, named leads, allowed duties and the cap only" do
    described_class.write!(project, enabled: %w[stalled critical_slip], lead_ids: [lead.id, "x"],
                                    duties: %w[decision_log nope], token_cap: -5)
    settings = described_class.for(project)

    expect(settings.enabled?("stalled")).to be(true)
    expect(settings.enabled?("idle_capacity")).to be(false)
    expect(settings.lead_ids).to eq([lead.id])
    expect(settings.duty_allowed?("decision_log")).to be(true)
    expect(settings.duty_allowed?("nope")).to be(false)
    expect(settings.token_cap).to eq(0)
    expect(Assistant::Proactive::Routing.leads(project)).to eq([]) # not a member
  end
end
