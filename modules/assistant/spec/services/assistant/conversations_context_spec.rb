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

RSpec.describe Assistant::Conversations::Context do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, firstname: "Sam", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search API") }

  let(:proposed) do
    Assistant::Action.create!(kind: "reassign", title: "Give it to Sam", tier: "t1", status: "proposed", project:, subject: work_package,
                              on_behalf_of: sam,
                              plan: { "steps" => [{ "op" => "update_work_package", "type" => "WorkPackage", "id" => work_package.id,
                                                    "attributes" => { "assignee" => "Sam" } }] })
  end
  let(:signal) do
    Assistant::Signal.create!(detector: "idle_capacity", fingerprint: "c-#{SecureRandom.hex(3)}", recipient: sam, project:,
                              subject: work_package, channel: "inline", deliver_at: Time.current, state: "pending", action: proposed,
                              payload: { "headline" => "Search API has had no owner for 26 days", "certainty" => "likely",
                                         "because" => ["No owner for 26 days", "Sam has 68 hours free"],
                                         "facts" => { "idle_days" => 26 },
                                         "options" => [{ "label" => "Give it to Sam", "consequence" => "Assigns and plans it",
                                                         "action_id" => proposed.id }] })
  end

  describe ".for" do
    it "knows notices and actions, and nothing else" do
      expect(described_class.for(signal)).to be_a(Assistant::Conversations::SignalContext)
      expect(described_class.for(proposed)).to be_a(Assistant::Conversations::ActionContext)
      expect(described_class.for(work_package)).to be_nil
    end
  end

  describe "visibility" do
    it "shows a notice only to the person it was for" do
      expect(described_class.for(signal).visible_to?(sam)).to be(true)
      expect(described_class.for(signal).visible_to?(ben)).to be(false)
    end

    it "shows an action to the person who delegated it or decided it, and to nobody else" do
      done = proposed.tap { it.update!(status: "executed", decided_by: ben) }

      expect(described_class.for(done).visible_to?(sam)).to be(true)
      expect(described_class.for(done).visible_to?(ben)).to be(true)
      expect(described_class.for(done).visible_to?(create(:user))).to be(false)
    end
  end

  describe "#material" do
    it "gives the assistant the facts, the basis, the options with their effects and the rule" do
      text = described_class.for(signal).material(sam)

      expect(text).to include("Search API has had no owner for 26 days", "No owner for 26 days", "Sam has 68 hours free",
                              "Assigns and plans it", "idle_days: 26", "idle_capacity", "a guess", "Why it is theirs:",
                              "work package ##{work_package.id}")
      expect(text.length).to be <= described_class::MATERIAL_LIMIT
    end

    it "tells about a receipt what was done, for whom and on what basis" do
      done = proposed.tap { it.update!(status: "executed", decided_by: sam, basis: [{ "kind" => "quote", "label" => "Planning", "quote" => "give it to Sam" }]) }
      text = described_class.for(done).material(sam)

      expect(text).to include("Give it to Sam", "Something already done", "update_work_package", "Planning: \"give it to Sam\"")
    end
  end

  it "titles by the main sentence and suggests questions that fit" do
    context = described_class.for(signal)

    expect(context.title(sam)).to eq("Search API has had no owner for 26 days")
    expect(context.chips(sam).size).to eq(3)
    expect(described_class.for(proposed).chips(sam)).to eq(I18n.t("assistant.thread.chips.notice"))
  end

  it "is what the agent works on when a conversation is about it" do
    conversation = Assistant::Conversation.new(user: sam, project:, context: signal)

    expect(conversation.page_subject).to eq(work_package)
    expect(Assistant::Reasoning::Situation.new(user: sam, project:, subject: signal).to_s)
      .to include("What this conversation is about", "Search API has had no owner for 26 days")
  end
end
