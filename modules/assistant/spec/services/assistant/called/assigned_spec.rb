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

RSpec.describe Assistant::Called::Assigned do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_package_comments work_package_assigned
                                          use_assistant])
  end
  shared_let(:fiona) { create(:user, member_with_roles: { project => role }) }
  shared_let(:review) { create(:status, name: "In review") }

  let(:work_package) do
    create(:work_package, project:, author: fiona, assigned_to: fiona, description: "Add page numbers to the PDF export.")
  end
  let(:journal) do
    User.execute_as(fiona) { WorkPackages::UpdateService.new(user: fiona, model: work_package).call(assigned_to_id: Assistant.user.id) }
    work_package.journals.reload.last
  end
  let(:agent) { instance_double(Assistant::Reasoning::Agent, run: Struct.new(:content).new(answer)) }
  let(:answer) { "I read the thread.\n=====\n## Requirements\n\nPage numbers at the bottom. ◌ Cover page: open." }

  before do
    Assistant::Membership.ensure_member!(project)
    create(:workflow, role:, type: work_package.type, old_status: work_package.status, new_status: review)
    allow(Assistant::Reasoning::Agent).to receive(:new).and_return(agent)
  end

  def progress = work_package.reload.journals.where(user: Assistant.user).where.not(notes: [nil, ""]).order(:id)

  it "leaves one progress line, then hands the draft back in the description and replaces that very line" do
    described_class.new(journal).call

    expect(progress.count).to eq(1)
    started = progress.sole
    action = Assistant::Action.find_by!(kind: "assigned_hand_back", subject: work_package)
    comment, update = action.steps
    expect(comment).to include("op" => "comment", "replace" => started.id)
    expect(comment.dig("attributes", "notes")).to include("I read the thread.")
    description = update.dig("attributes", "description")
    expect(description).to start_with("Add page numbers to the PDF export.")
    expect(description).to include("## Draft by the AI assistant").and include("◌ Cover page: open.")
    expect(update["attributes"]).to include("assigned_to_id" => fiona.id)
    expect(work_package.attachments).to be_empty
  end

  it "puts a revised draft in the place of the earlier one and keeps what was asked" do
    work_package.update_columns(
      description: "Add page numbers to the PDF export.\n\n---\n\n## Draft by the AI assistant\n\nOld draft"
    )

    described_class.new(journal).call

    description = Assistant::Action.find_by!(kind: "assigned_hand_back").steps.last.dig("attributes", "description")
    expect(description).to start_with("Add page numbers to the PDF export.\n\n---")
    expect(description).to include("Page numbers at the bottom.")
    expect(description).not_to include("Old draft")
  end

  context "when it cannot do the work" do
    let(:answer) { "CANNOT: I have no access to the licence server." }

    it "says so in the line it left, and gives the work package back" do
      described_class.new(journal).call

      expect(progress.sole.notes).to include("I have no access to the licence server.")
      expect(work_package.reload.assigned_to).to eq(fiona)
      expect(Assistant::Action.where(kind: "assigned_hand_back")).to be_empty
    end
  end
end
