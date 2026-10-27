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

RSpec.describe Assistant::Duties::ReleaseWatch, "news for a passed phase gate" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant news]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant manage_news view_news
                                          view_project_phases])
  end
  shared_let(:lead) { create(:user, member_with_roles: { project => role }) }
  shared_let(:design) { create(:project_phase_definition, :with_finish_gate, name: "Design") }
  shared_let(:build) { create(:project_phase_definition, :with_start_gate, name: "Build") }
  shared_let(:done) { create(:status, is_closed: true) }

  let(:duty) { Assistant::Duty.create!(project:, kind: "release_watch", delegator: lead) }
  let(:llm) { instance_double(Assistant::Llm) }

  before do
    allow(Assistant::Llm).to receive(:configured?).and_return(true)
    allow(llm).to receive(:json).and_return("title" => "Design is done", "summary" => "The design phase ended.",
                                            "description" => "## Design\n\nDone: #1.")
    Assistant::Membership.ensure_member!(project)
    create(:work_package, project:, status: done, project_phase_definition_id: design.id)
  end

  def run(now: Time.current) = described_class.new(duty, now:, llm:).call

  def phases(next_started_on:)
    create(:project_phase, :skip_validate, project:, definition: design,
                                           start_date: Date.current - 20, finish_date: Date.current - 2)
    create(:project_phase, :skip_validate, project:, definition: build,
                                           start_date: next_started_on, finish_date: Date.current + 20)
  end

  it "drafts one piece of news, a T3 proposal nobody executes, and not a second time" do
    phases(next_started_on: Date.current - 1)

    first = run
    second = run

    action = Assistant::Action.find_by!(kind: "phase_news", project:)
    expect(first.action_ids).to eq([action.id])
    expect(action).to have_attributes(status: "proposed", tier: "t3", subject: Project::Phase.find_by(definition: design))
    expect(action.steps.sole).to include("op" => "publish_news")
    expect(second.action_ids).not_to include(action.id)
    expect(Assistant::Action.where(kind: "phase_news").count).to eq(1)
  end

  it "waits until the next phase has started" do
    phases(next_started_on: Date.current + 5)

    run

    expect(Assistant::Action.where(kind: "phase_news")).to be_empty
  end

  it "leaves phases whose gate was passed long ago" do
    phases(next_started_on: Date.current - 10)

    run

    expect(Assistant::Action.where(kind: "phase_news")).to be_empty
  end
end
