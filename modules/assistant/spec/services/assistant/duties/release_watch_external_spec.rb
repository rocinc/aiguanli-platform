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

RSpec.describe Assistant::Duties::ReleaseWatch, "reminders to the outside" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant manage_versions])
  end
  shared_let(:lead) { create(:user, member_with_roles: { project => role }) }
  shared_let(:done) { create(:status, is_closed: true) }

  let(:release_day) { Assistant::Facts.add_working_days(Date.current, 3) }
  let(:version) { create(:version, project:, name: "v2.0", effective_date: release_day, status: "open") }
  let(:scope) { { "version_id" => version.id.to_s, "external_to" => "ops@client.example, not-an-address" } }
  let(:duty) { Assistant::Duty.create!(project:, kind: "release_watch", delegator: lead, scope:) }

  before do
    Assistant::Membership.ensure_member!(project)
    create(:work_package, project:, status: done, version:)
    create(:work_package, project:, version:)
  end

  def run = described_class.new(duty, now: Time.current).call

  it "drafts one reminder to the listed addresses, a T3 mail nobody sends before it is read, and not a second time" do
    first = run
    second = run

    action = Assistant::Action.find_by!(kind: "external_notice", project:)
    expect(first.action_ids).to include(action.id)
    expect(second.action_ids).not_to include(action.id)
    expect(Assistant::Action.where(kind: "external_notice").count).to eq(1)
    expect(action).to have_attributes(status: "proposed", tier: "t3", subject: version, on_behalf_of: lead)
    step = action.steps.sole
    expect(step["op"]).to eq("send_mail")
    expect(step["attributes"]).to include("to" => ["ops@client.example"], "signed_for" => lead.name)
    expect(step["attributes"]["body"]).to include("2 items", "1 done", "1 still open")
    expect(Assistant::Signal.where(action:, recipient: lead)).to exist
  end

  it "does not draft when no outside address is listed or the date is still far off" do
    duty.update!(scope: scope.except("external_to"))
    run
    duty.update!(scope:)
    version.update!(effective_date: Assistant::Facts.add_working_days(Date.current, 12))
    run

    expect(Assistant::Action.where(kind: "external_notice")).to be_empty
  end

  it "sends the mail only when it is confirmed, signed as the assistant on behalf of whoever confirmed it" do
    run
    action = Assistant::Action.find_by!(kind: "external_notice")
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs { Assistant::Actions::Execute.call(action, decided_by: lead) }

    mail = ActionMailer::Base.deliveries.sole
    expect(mail.to).to eq(["ops@client.example"])
    expect(mail.subject).to include("v2.0")
    expect(mail.text_part.body.to_s).to include("v2.0").and include(lead.name)
    expect(action.reload.status).to eq("executed")
  end

  it "sends nothing while the draft is only being previewed" do
    run
    action = Assistant::Action.find_by!(kind: "external_notice")
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs { Assistant::Actions::Preview.new(steps: action.steps, user: lead).call }

    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
