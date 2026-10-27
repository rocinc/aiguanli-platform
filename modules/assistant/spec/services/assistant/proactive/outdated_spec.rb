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

RSpec.describe Assistant::Proactive::Outdated do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:sam) { create(:user, firstname: "Sam", lastname: "S", member_with_roles: { project => role }) }

  let(:since) { 3.days.ago }
  let(:work_package) do
    travel_to(5.days.ago) { create(:work_package, project:, assigned_to: sam, due_date: Date.new(2026, 10, 9)) }
  end

  def signal_for(detector, **payload)
    Assistant::Signal.create!(detector:, fingerprint: "#{detector}:#{work_package.id}", recipient: sam, project:, subject: work_package,
                              channel: "inline", state: "delivered", deliver_at: since,
                              payload: { "headline" => "x", "facts" => { "since" => since.iso8601 } }.merge(payload.stringify_keys))
  end

  it "takes back a stalled notice once the work package has news" do
    signal = signal_for("stalled")
    described_class.retract!(project)
    expect(signal.reload.outcome).to be_nil

    work_package.add_journal(user: sam, notes: "Back on it")
    work_package.save!(validate: false)
    described_class.retract!(project)

    expect(signal.reload).to have_attributes(outcome: "resolved", state: "dismissed")
    expect(signal.payload["stale_reason"]).to include("##{work_package.id}")
  end

  it "takes back a notice about a done pull request once the status has moved" do
    signal = signal_for("merged_not_advanced")
    described_class.retract!(project)
    expect(signal.reload.outcome).to be_nil

    Assistant::Event.create!(kind: "work_package.updated", subject: work_package, project:, actor: sam,
                             changes_made: { "status_id" => [1, 2] }, created_at: since + 1.hour)
    described_class.retract!(project)

    expect(signal.reload.outcome).to eq("resolved")
  end

  it "takes back a proposed change the person has made by hand, and what it offered with it" do
    action = Assistant::Actions::Propose.call(
      kind: "said_change", title: "Due 10/16", on_behalf_of: sam, project:, subject: work_package, auto_execute: false,
      steps: [{ "op" => "update_work_package", "type" => "WorkPackage", "id" => work_package.id, "attributes" => { "due_date" => "2026-10-16" } }]
    )
    signal = signal_for("said_change", options: [{ "label" => "Do it", "action_id" => action.id }])
    signal.update!(action:)
    described_class.retract!(project)
    expect(signal.reload.outcome).to be_nil

    work_package.update_columns(due_date: Date.new(2026, 10, 16))
    described_class.retract!(project)

    expect(signal.reload.outcome).to eq("resolved")
    expect(action.reload.status).to eq("superseded")
  end
end
