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

RSpec.describe Assistant::Duties::Onboarding do
  shared_let(:project) { create(:project, name: "Billing", enabled_module_names: %w[work_package_tracking assistant wiki]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant view_wiki_pages edit_wiki_pages])
  end
  shared_let(:lead) { create(:user, member_with_roles: { project => role }) }
  shared_let(:newcomer) { create(:user, firstname: "Nia", lastname: "N") }
  shared_let(:work_package) { create(:work_package, project:, subject: "Invoice export", assigned_to: newcomer) }

  let(:duty) do
    Assistant::Duty.create!(project:, kind: "onboarding", delegator: lead).tap { it.update_columns(created_at: 2.days.ago) }
  end

  before do
    allow(Assistant::Llm).to receive(:configured?).and_return(false)
    Assistant::Membership.ensure_member!(project)
    project.wiki || create(:wiki, project:)
    project.reload
  end

  def join!(person, joined: 1.hour.ago)
    member = create(:member, project:, principal: person, roles: [role])
    member.update_columns(created_at: joined)
  end

  it "drafts one wiki page for the delegator when someone joined, and not again" do
    join!(newcomer)

    2.times { Assistant::Duties::Runner.new(duty, now: Time.current).call }

    actions = Assistant::Action.where(kind: "onboarding_page", project:)
    expect(actions.count).to eq(1)
    expect(actions.first).to have_attributes(status: "proposed", subject: newcomer, on_behalf_of: lead)
    expect(actions.first.steps.sole["attributes"]["title"]).to eq("Onboarding: Nia N")
    expect(Assistant::Signal.where(detector: "duty_onboarding", recipient: lead).count).to eq(1)
  end

  it "leaves people who joined before the duty, the delegator and the assistant alone" do
    join!(newcomer, joined: 5.days.ago)
    Member.where(project:, principal: [lead, Assistant.user]).update_all(created_at: 1.hour.ago)

    result = Assistant::Duties::Runner.new(duty, now: Time.current).call

    expect(result.produced).to be(false)
    expect(Assistant::Action.where(kind: "onboarding_page")).to be_empty
  end

  it "waits for the work handed over in the same sitting" do
    join!(newcomer, joined: 2.minutes.ago)

    expect(Assistant::Duties::Runner.new(duty, now: Time.current).call.produced).to be(false)
  end
end
