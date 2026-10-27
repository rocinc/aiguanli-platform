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

RSpec.describe Assistant::Reasoning::Tools::ProposeTool do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search API", assigned_to: sam, due_date: Date.current + 5) }

  let(:steps) do
    [{ "op" => "update_work_package", "work_package" => "##{work_package.id}",
       "attributes" => { "due_date" => (Date.current + 9).iso8601 } }]
  end

  def propose(extra = {})
    context = Assistant::Reasoning::Tools::Context.new(user: sam, project:)
    result = User.execute_as(sam) { described_class.new(context).call({ "title" => "Move it", "steps" => steps }.merge(extra)) }
    Assistant::Action.find(result["action_id"])
  end

  it "does a change of the person's own at once, as it always did" do
    expect(propose).to have_attributes(tier: "t1", status: "executed")
  end

  it "only prepares it when asked to hold, so it waits as a card for the person to press" do
    expect(propose("hold" => true)).to have_attributes(tier: "t1", status: "proposed")
    expect(work_package.reload.due_date).to eq(Date.current + 5)
  end
end
