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

RSpec.describe Assistant::Duties::Base, "offering to a delegator who muted the duty" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:ben) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: ben) }

  let(:duty) { Assistant::Duty.create!(project:, kind: "weekly_status", delegator: ben) }
  let(:handler) do
    Class.new(described_class) do
      def call = nil

      def offer_one(action) = offer(action, headline: "Weekly status")
    end.new(duty)
  end
  let(:action) do
    Assistant::Actions::Propose.call(
      kind: "weekly_status", title: "Weekly status", on_behalf_of: ben, project:, subject: work_package, auto_execute: false,
      steps: [{ "op" => "comment", "as" => "person", "type" => "WorkPackage", "id" => work_package.id,
                "attributes" => { "notes" => "On track" } }]
    )
  end

  before { Assistant::Membership.ensure_member!(project) }

  it "offers a signal while the duty is not muted" do
    expect { handler.offer_one(action) }.to change { Assistant::Signal.where(detector: "duty_weekly_status").count }.by(1)
  end

  it "creates no signal and withdraws the action once the person muted it" do
    Assistant::Preference.for(ben).mute!("duty_weekly_status")

    expect { handler.offer_one(action) }.not_to change(Assistant::Signal, :count)
    expect(action.reload.status).to eq("superseded")
  end

  it "creates no signal once the person muted it in this project only" do
    Assistant::Preference.for(ben).mute_in!("duty_weekly_status", project)

    expect { handler.offer_one(action) }.not_to change(Assistant::Signal, :count)
  end

  it "does not ask whether the duty is still needed when that is muted" do
    Assistant::Preference.for(ben).mute!("duty_unused")
    duty.update!(unseen_runs: 5)
    allow(duty).to receive(:handler).and_return(Class.new(described_class) { def call = Assistant::Duties::Base::Result.nothing })

    expect { Assistant::Duties::Runner.new(duty).call }.not_to change(Assistant::Signal, :count)
  end
end
