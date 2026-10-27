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
require_relative "../../../support/intent_helpers"

RSpec.describe Assistant::Reasoning::Tools::InboxTool do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:hidden_project) { create(:project, enabled_module_names: %w[work_package_tracking]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:ada) { create(:user, firstname: "Ada", lastname: "A", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }

  def work_package(subject) = create(:work_package, project:, subject:, author: ben)

  def notify(wp, reason, **) = create(:notification, recipient: ada, resource: wp, reason:, actor: ben, **)

  def today = Date.current.iso8601

  def triage(user = ada) = described_class.new(Assistant::Reasoning::Tools::Context.new(user:, project:)).call({})

  let!(:assigned) { work_package("Assigned").tap { notify(it, :assigned) } }
  let!(:mentioned) { work_package("Mentioned").tap { notify(it, :mentioned) } }
  let!(:asked) do
    work_package("Asked").tap do |wp|
      notify(wp, :watched)
      create_intent(project:, subject: wp, owner: ben, counterparty: ada, kind: "question", status: "open",
                    title: "谁来评审", quote: "谁来评审这个方案？")
    end
  end
  let!(:promised) do
    work_package("Promised").tap do |wp|
      notify(wp, :watched)
      create_intent(project:, subject: wp, owner: ada, kind: "commitment", status: "open", said_due_expression: "两天",
                    title: "修", quote: "两天内修好")
    end
  end

  let!(:requested) do
    work_package("Requested").tap do |wp|
      notify(wp, :commented)
      create_intent(project:, subject: wp, owner: ada, counterparty: ben, kind: "commitment", status: "open", strength: "requested",
                    title: "确认文案", quote: "周三前能帮我确认一下吗？")
    end
  end

  before do
    work_package("Watched").tap { notify(it, :watched) }
    work_package("Commented").tap { notify(it, :commented) }
    work_package("Read already").tap { notify(it, :assigned, read_ian: true) }
    create(:notification, recipient: ada, resource: create(:work_package, project: hidden_project), reason: :assigned, actor: ben)
  end

  it "separates what needs the person from what can wait, counting only what they can see and have not read" do
    result = triage

    expect(result["unread"]).to eq(7)
    expect(result.dig("needs_you", "count")).to eq(5)
    expect(result.dig("needs_you", "items").map { it.dig("work_package", "subject") })
      .to contain_exactly("Assigned", "Mentioned", "Asked", "Requested", "Promised")
    expect(result["can_wait"]).to eq("count" => 2, "by_reason" => { "watched" => 1, "commented" => 1 })
  end

  it "says why each one needs the person, with the words behind it" do
    items = triage.dig("needs_you", "items").index_by { it.dig("work_package", "subject") }

    expect(items["Assigned"]["why"]).to eq([{ "kind" => "assigned_to_you" }])
    expect(items["Mentioned"]["why"]).to eq([{ "kind" => "mentioned" }])
    expect(items["Asked"]["why"]).to eq([{ "kind" => "waiting_for_your_reply", "question" => "谁来评审这个方案？",
                                           "asked_by" => "Ben B", "on" => today }])
    expect(items["Requested"]["why"]).to eq([{ "kind" => "waiting_for_your_reply", "question" => "周三前能帮我确认一下吗？",
                                               "asked_by" => "Ben B", "on" => today }])
    expect(items["Promised"]["why"]).to eq([{ "kind" => "your_promise", "said" => "两天", "on" => today }])
    expect(items["Asked"]["from"]).to eq("Ben B")
  end

  it "does not mark anything as read" do
    before = Notification.order(:id).pluck(:id, :read_ian, :updated_at)

    triage

    expect(Notification.order(:id).pluck(:id, :read_ian, :updated_at)).to eq(before)
  end

  it "reads only the person's own inbox" do
    result = triage(ben)

    expect(result).to include("unread" => 0)
    expect(result.dig("needs_you", "count")).to eq(0)
  end

  it "is offered to the panel and read-only" do
    expect(Assistant::Reasoning::Tools.read_only).to include(described_class)
    expect(described_class.tool_name).to eq("inbox_triage")
  end
end
