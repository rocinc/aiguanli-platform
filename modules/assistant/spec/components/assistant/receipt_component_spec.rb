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
require "rails_helper"

RSpec.describe Assistant::ReceiptComponent, type: :component do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, firstname: "Sam", lastname: "Lee", member_with_roles: { project => role }) }
  shared_let(:ada) { create(:user, firstname: "Ada", lastname: "Ng", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search API") }

  let(:preview) do
    {
      "success" => true, "affected_user_ids" => [], "version_slips" => [],
      "cascaded" => ["gid://openproject/WorkPackage/999"],
      "changes" => [
        { "gid" => work_package.to_gid.to_s, "type" => "WorkPackage", "id" => work_package.id, "kind" => "work_package",
          "label" => "##{work_package.id} Search API", "detail" => {}, "created" => false,
          "changes" => { "due_date" => ["2026-09-23", "2026-09-30"] } },
        { "gid" => "gid://openproject/WorkPackage/999", "type" => "WorkPackage", "id" => 999, "kind" => "work_package",
          "label" => "#999 Release notes", "detail" => {}, "created" => false,
          "changes" => { "start_date" => ["2026-09-24", "2026-10-01"] } }
      ]
    }
  end
  let(:executed_at) { 2.hours.ago }
  let(:status) { "executed" }
  let(:inverse) { [{ "op" => "revert", "type" => "WorkPackage", "id" => work_package.id, "attributes" => {}, "expect" => {} }] }
  let(:action) do
    Assistant::Action.create!(kind: "reschedule", title: "Move Search API", tier: "t1", status:, project:, subject: work_package,
                              on_behalf_of: sam, decided_by: sam, executed_at:, preview:, inverse:,
                              plan: { "steps" => [{ "op" => "update_work_package", "type" => "WorkPackage",
                                                    "id" => work_package.id, "attributes" => { "due_date" => "2026-09-30" } }] },
                              basis: [{ "kind" => "quote", "label" => "Sprint 6 planning", "quote" => "push it" }])
  end

  def receipt(user = sam, **) = render_inline(described_class.new(action:, user:, **))

  it "says in one sentence what was done, on what basis and when, and lists what moved along" do
    receipt

    sentence = page.find("[data-test-selector='assistant-receipt-sentence']").text
    expect(sentence).to match(%r{\A(Changed Finish date to 9/30 \(Wed\) of|Updated Finish date of) ##{work_package.id}\z})
    expect(sentence.length).to be <= Assistant::Receipts::Sentence::LIMIT
    expect(page).to have_test_selector("assistant-receipt-reason", text: "based on Sprint 6 planning")
    expect(page).to have_test_selector("assistant-receipt-when", text: "Today")
    expect(page).to have_test_selector("assistant-receipt-cascade", text: "#999 Release notes", visible: :all)
    expect(page).to have_test_selector("assistant-action-undo")
  end

  it "lets the person say something about it at either density" do
    %i[full line].each do |density|
      receipt(density:)
      expect(page).to have_css("[data-test-selector='assistant-say'][data-assistant-context='#{action.to_gid}']", visible: :all)
    end
  end

  it "names whom it acted for when someone else reads it" do
    receipt(ada)

    expect(page).to have_test_selector("assistant-receipt-reason", text: "for Sam Lee, based on Sprint 6 planning")
  end

  context "when it was taken back" do
    let(:status) { "undone" }

    it "says so and offers no undo" do
      receipt

      expect(page).to have_test_selector("assistant-receipt-undone", text: "Undone")
      expect(page).to have_no_test_selector("assistant-action-undo")
    end
  end

  context "when it is older than the undo window" do
    let(:executed_at) { 8.days.ago }

    it "previews before undoing" do
      receipt

      expect(page).to have_no_test_selector("assistant-action-undo")
      expect(page).to have_link("Undo…", href: "/assistant/actions/#{action.id}")
    end
  end
end
