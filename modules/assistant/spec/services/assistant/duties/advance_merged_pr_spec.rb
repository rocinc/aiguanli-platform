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

RSpec.describe Assistant::Duties::AdvanceMergedPr do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_package_comments use_assistant]) }
  shared_let(:ada) { create(:user, firstname: "Ada", lastname: "N", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: ada) }

  let(:duty) { Assistant::Duty.create!(project:, kind: "advance_merged_pr", delegator: ada) }

  before { Assistant::Membership.ensure_member!(project) }

  def pull_request(number: 412, **) = create(:github_pull_request, number:, **)

  def run! = Assistant::Duties::Runner.new(duty).call

  def sentence(action) = Assistant::Receipts::Sentence.new(action, user: ada).call.text.sub(Assistant::Receipts::Sentence::MARK, "PR #412")

  it "links a pull request that writes the number in its title, and says so in a receipt" do
    pr = pull_request(title: "Fix search ##{work_package.id}")

    result = run!
    action = Assistant::Action.find(result.action_ids.sole)

    expect(pr.reload.work_packages).to eq([work_package])
    expect(action).to have_attributes(kind: "link_pull_request", status: "executed", tier: "t1", subject: work_package)
    expect(sentence(action)).to eq("Linked PR #412 to ##{work_package.id}")
    I18n.with_locale(:"zh-CN") { expect(sentence(action)).to eq("已把 PR #412 关联到 ##{work_package.id}") }
  end

  it "reads as a receipt line with the pull request linked, and as a consequence line" do
    pull_request(title: "Fix search ##{work_package.id}")
    action = Assistant::Action.find(run!.action_ids.sole)

    html = ApplicationController.renderer.render(Assistant::ReceiptComponent.new(action:, user: ada, density: :full), layout: false)
    line = Capybara.string(html).find("[data-test-selector='assistant-receipt-sentence']")

    expect(line.text).to eq("Linked PR #412 to ##{work_package.id}")
    expect(line).to have_link("PR #412", href: "https://github.com/test_user/test_repo/pull/412")
    expect(Assistant::Consequences.new(action.preview, user: ada).summary).to eq("PR #412: Linked work packages none → ##{work_package.id}")
  end

  it "links a pull request that closes the work package by name in its text" do
    pr = pull_request(body: "This fixes ##{work_package.id}.")

    run!

    expect(pr.reload.work_packages).to eq([work_package])
  end

  it "takes the link back, and does not make it again" do
    pr = pull_request(title: "Fix search ##{work_package.id}")
    action = Assistant::Action.find(run!.action_ids.sole)

    Assistant::Actions::Undo.call(action, user: ada)
    duty.update!(last_run_at: nil)

    expect(pr.reload.work_packages).to be_empty
    expect(run!.action_ids).to be_empty
    expect(Assistant::Action.where(kind: "link_pull_request").count).to eq(1)
  end

  it "leaves alone what the platform links by itself, what is linked already, and numbers it cannot place" do
    other = create(:work_package)
    host_way = pull_request(number: 1, title: "Fix search OP##{work_package.id}")
    linked = pull_request(number: 2, title: "Fix search ##{work_package.id}", work_packages: [work_package])
    own_number = pull_request(number: work_package.id, title: "Fix search (##{work_package.id})")
    elsewhere = pull_request(number: 4, title: "Fix search ##{other.id}")
    stranger = pull_request(number: 5, title: "Fix search #99999999")

    expect(run!.action_ids).to be_empty
    expect([host_way, own_number, elsewhere, stranger].map { it.reload.work_packages }).to all(be_empty)
    expect(linked.reload.work_packages).to eq([work_package])
  end
end
