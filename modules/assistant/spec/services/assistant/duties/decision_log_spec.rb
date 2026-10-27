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
require_relative "../../../support/intent_helpers"

RSpec.describe Assistant::Duties::DecisionLog do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking wiki assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant view_wiki_pages edit_wiki_pages
                                          view_wiki_edits delete_wiki_pages])
  end
  shared_let(:ada) { create(:user, firstname: "Ada", lastname: "N", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: ada) }

  let(:duty) { Assistant::Duty.create!(project:, kind: "decision_log", delegator: ada, scope: { "ceiling" => "draft" }) }

  before do
    Assistant::Membership.ensure_member!(project)
    project.wiki || create(:wiki, project:)
  end

  def decide!(title)
    create_intent(project:, subject: work_package, owner: ada, kind: "decision", status: "active", title:, quote: title)
  end

  def run! = Assistant::Duties::Runner.new(duty).call

  it "keeps one draft per page and adds later decisions to it" do
    decide!("Use two permission levels")
    first = run!
    draft = Assistant::Action.find(first.action_ids.sole)

    decide!("Ship export in v1.1")
    second = run!

    expect(second.action_ids).to eq([draft.id])
    expect(Assistant::Action.where(kind: "decision_log").count).to eq(1)
    expect(Assistant::Signal.where(detector: "duty_decision_log").count).to eq(1)
    expect(draft.reload.steps.first.dig("attributes", "text")).to include("Use two permission levels", "Ship export in v1.1")
  end

  it "starts a new draft once the earlier one was decided" do
    decide!("Use two permission levels")
    draft = Assistant::Action.find(run!.action_ids.sole)
    draft.update!(status: "rejected")

    decide!("Ship export in v1.1")

    expect(run!.action_ids.sole).not_to eq(draft.id)
    expect(Assistant::Action.where(kind: "decision_log").count).to eq(2)
  end

  it "does not count a draft that is only added to as one nobody looked at" do
    decide!("Use two permission levels")
    4.times do |i|
      decide!("Decision #{i}")
      duty.update!(last_run_at: nil)
      travel_to((i + 1).weeks.from_now) { run! }
    end

    expect(duty.reload.unseen_runs).to eq(0)
    expect(Assistant::Signal.where(detector: "duty_unused")).to be_empty
  end
end
