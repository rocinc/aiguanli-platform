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

RSpec.describe Assistant::Reasoning::Tools::PreviewTool do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages manage_versions use_assistant])
  end
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:version) { create(:version, project:, name: "v1.1 商业化版", effective_date: Date.new(2026, 10, 20)) }

  def preview(steps)
    context = Assistant::Reasoning::Tools::Context.new(user: sam, project:)
    User.execute_as(sam) { described_class.new(context).call({ "steps" => steps }) }
  end

  it "previews moving a version's date without changing it" do
    result = preview([{ "op" => "update_version", "version" => "v1.1 商业化版",
                        "attributes" => { "effective_date" => "2026-10-30" } }])

    expect(result).to include("success" => true)
    expect(version.reload.effective_date).to eq(Date.new(2026, 10, 20))
  end
end
