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
#++

require "spec_helper"

RSpec.describe Assistant::Duties::Runner do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:ben) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: ben) }

  let(:duty) { Assistant::Duty.create!(project:, kind: "weekly_status", delegator: ben) }

  before { Assistant::Membership.ensure_member!(project) }

  def draft!(at)
    travel_to(at) do
      Assistant::Actions::Propose.call(
        kind: "weekly_status", title: "Weekly status", on_behalf_of: ben, project:, subject: work_package, auto_execute: false,
        steps: [{ "op" => "comment", "as" => "person", "type" => "WorkPackage", "id" => work_package.id,
                  "attributes" => { "notes" => "On track #{at.to_i}" } }]
      )
    end
  end

  def run_producing(action, at)
    result = Assistant::Duties::Base::Result.new(summary: "1", action_ids: [action.id], produced: true)
    allow(duty).to receive(:handler).and_return(Class.new(Assistant::Duties::Base) { define_method(:call) { result } })
    travel_to(at) { described_class.new(duty, now: at).call }
  end

  it "counts a draft as unseen only after it waited a week without being opened" do
    t0 = Time.zone.local(2026, 10, 5, 9)
    run_producing(draft!(t0), t0)
    expect(duty.reload.unseen_runs).to eq(0)

    run_producing(draft!(t0 + 3.days), t0 + 3.days)
    expect(duty.reload.unseen_runs).to eq(0)

    run_producing(draft!(t0 + 14.days), t0 + 14.days)
    expect(duty.reload.unseen_runs).to eq(1)
  end

  it "starts over when the earlier draft was decided" do
    t0 = Time.zone.local(2026, 10, 5, 9)
    duty.update!(unseen_runs: 3)
    first = draft!(t0)
    run_producing(first, t0)
    first.update!(status: "rejected")

    run_producing(draft!(t0 + 8.days), t0 + 8.days)

    expect(duty.reload.unseen_runs).to eq(0)
  end

  it "asks whether the duty is still needed after four drafts that waited a week unopened" do
    t0 = Time.zone.local(2026, 10, 5, 9)
    5.times { |i| run_producing(draft!(t0 + (i * 8).days), t0 + (i * 8).days) }

    expect(duty.reload.unseen_runs).to eq(4)
    expect(Assistant::Signal.where(detector: "duty_unused", recipient: ben)).to exist
  end

  it "words that question in the delegator's language, with a basis and a way to act" do
    ben.update_column(:language, "zh-CN")
    t0 = Time.zone.local(2026, 10, 5, 9)
    5.times { |i| run_producing(draft!(t0 + (i * 8).days), t0 + (i * 8).days) }

    payload = Assistant::Signal.find_by!(detector: "duty_unused", recipient: ben).payload
    expect(payload["headline"]).to include("还需要继续吗")
    expect(payload["because"]).to eq(["最近 4 次产出都没人打开"])
    expect(payload["options"].first["url"]).to include("tab=duties")
  end
end
