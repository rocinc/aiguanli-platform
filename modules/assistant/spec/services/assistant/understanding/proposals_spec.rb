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

RSpec.describe Assistant::Understanding::Proposals do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant
                                          manage_versions assign_versions])
  end
  shared_let(:ada) { create(:user, firstname: "Ada", lastname: "Lovelace", member_with_roles: { project => role }) }
  shared_let(:quinn) { create(:user, firstname: "Quinn", lastname: "Hughes", member_with_roles: { project => role }) }
  shared_let(:release) { create(:version, project:, name: "1.4", effective_date: Date.new(2026, 12, 1)) }

  let(:monday) { Date.new(2026, 10, 12) }
  let!(:work_package) { create(:work_package, project:, assigned_to: ada, start_date: monday, due_date: monday + 2) }

  before do
    allow(Setting).to receive(:working_days).and_return([1, 2, 3, 4, 5])
    Assistant::Membership.ensure_member!(project)
  end

  def comment(text, user:)
    work_package.add_journal(user:, notes: text)
    work_package.save!(validate: false)
    work_package.journals.reload.last
  end

  def change(field, value, quote, certainty: "certain", target: "this", shift: false)
    { "target" => target, "field" => field, "value" => value, "shift" => shift, "quote" => quote, "certainty" => certainty }
  end

  it "moves the assignee's own work a week at once when they say so firmly" do
    journal = comment("这个延期一周吧。", user: ada)

    action = described_class.for(journal, [change("due_date", { "kind" => "working_days", "value" => 5 }, "这个延期一周吧",
                                                  shift: true)]).first

    expect(action).to have_attributes(status: "executed", tier: "t1")
    expect(work_package.reload).to have_attributes(start_date: monday + 7, due_date: monday + 9)
  end

  it "asks before giving the work to someone else, even when the speaker is sure" do
    journal = comment("改成 Quinn 来做吧。", user: ada)

    action = described_class.for(journal, [change("assignee", "Quinn", "改成 Quinn 来做吧")]).first

    expect(action).to have_attributes(status: "proposed", tier: "t2")
    expect(action.steps.first["attributes"]).to eq("assigned_to_id" => quinn.id)
    expect(Assistant::Signal.where(action:, recipient: ada).pluck(:channel)).to contain_exactly("inline", "brief")
    expect(work_package.reload.assigned_to).to eq(ada)
  end

  it "only proposes when the speaker is neither assignee nor accountable" do
    journal = comment("这个延期一周吧。", user: quinn)

    action = described_class.for(journal, [change("due_date", { "kind" => "working_days", "value" => 5 }, "这个延期一周吧",
                                                  shift: true)]).first

    expect(action).to have_attributes(status: "proposed")
    expect(work_package.reload.due_date).to eq(monday + 2)
  end

  it "puts the work into a version named exactly, and drops a name that matches nothing" do
    journal = comment("放到 1.4 吧，或者 2.0。", user: quinn)

    actions = described_class.for(journal, [change("version", "1.4", "放到 1.4 吧"), change("version", "2.0", "2.0")])

    expect(actions.size).to eq(1)
    expect(actions.first.steps.first["attributes"]).to eq("version_id" => release.id)
  end

  it "does not propose the same change twice, and replaces it when an edit changes the value" do
    bo = create(:user, firstname: "Bo", member_with_roles: { project => role })
    journal = comment("改成 Quinn 来做吧。", user: ada)
    said = [change("assignee", quinn.id, "改成 Quinn 来做吧")]

    first = described_class.for(journal, said).first
    expect(described_class.for(journal, said)).to be_empty

    journal.update_columns(notes: "改成 Bo 来做吧。")
    second = described_class.for(journal, [change("assignee", bo.id, "改成 Bo 来做吧")]).first

    expect(first.reload.status).to eq("superseded")
    expect(Assistant::Signal.live.where(action: first)).to be_empty
    expect(second).to have_attributes(status: "proposed")
    expect(second.steps.first["attributes"]).to eq("assigned_to_id" => bo.id)
  end

  context "when it is said in a meeting" do
    shared_let(:viewer) { create(:project_role, permissions: %i[view_work_packages use_assistant view_meetings]) }
    shared_let(:host) { create(:user, firstname: "Hal", member_with_roles: { project => role }) }
    shared_let(:guest_host) { create(:user, firstname: "Gus", member_with_roles: { project => viewer }) }

    def agenda_item(author:, presenter: quinn)
      meeting = create(:meeting, project:, author:, start_time: monday.to_time + 10.hours)
      create(:meeting_agenda_item, meeting:, author:, presenter:, title: "Search", notes: "这个延期一周吧",
                                   work_package:, item_type: :work_package)
    end

    let(:week_later) { change("due_date", { "kind" => "working_days", "value" => 5 }, "这个延期一周吧", shift: true) }

    it "waits for the host even when it is certain and the host owns the work" do
      work_package.update_columns(assigned_to_id: host.id)
      item = agenda_item(author: host)

      action = described_class.for(item, [week_later]).first

      expect(action).to have_attributes(status: "proposed", on_behalf_of: host)
      signal = Assistant::Signal.find_by(action:, channel: "brief")
      expect(signal.recipient).to eq(host)
      expect(signal.payload["because"].first).to eq("Presented by #{quinn.name}")
      expect(action.basis_entries.first.label).to include("item 1")
    end

    it "asks the accountable instead when the host may not change the work" do
      work_package.update_columns(responsible_id: ada.id)
      item = agenda_item(author: guest_host)

      action = described_class.for(item, [week_later]).first

      expect(action).to have_attributes(status: "proposed", on_behalf_of: ada)
      expect(Assistant::Signal.where(action:).pluck(:recipient_id).uniq).to eq([ada.id])
    end

    it "tells the decider's meeting page to reload the frame under the item" do
      allow(Assistant::SourceSignalsComponent).to receive(:broadcast_reload)
      item = agenda_item(author: host)

      described_class.for(item, [week_later])

      expect(Assistant::SourceSignalsComponent).to have_received(:broadcast_reload).with(item, [host])
    end
  end

  it "drops a change whose target or quote is not in the text" do
    journal = comment("往后挪挪吧。", user: ada)

    expect(described_class.for(journal, [change("due_date", { "kind" => "working_days", "value" => 2 }, "延期两天", shift: true),
                                         change("assignee", quinn.id, "往后挪挪", target: "#999999")])).to be_empty
  end
end
