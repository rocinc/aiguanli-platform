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

RSpec.describe Assistant::Reasoning::StepBuilder do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:version) { create(:version, project:, name: "v1.1 商业化版") }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search API") }

  let(:context) { Assistant::Reasoning::Tools::Context.new(user: sam, project:) }

  def build(*steps) = described_class.new(context).call(steps)

  describe "update_version" do
    it "finds the version by its name and gives the step the type and id the action runs on" do
      step = build({ "op" => "update_version", "version" => "v1.1", "attributes" => { "effective_date" => "2026-10-30" } }).first

      expect(step).to include("op" => "update_version", "type" => "Version", "id" => version.id,
                              "attributes" => { "effective_date" => "2026-10-30" })
      expect(step).not_to have_key("version")
    end

    it "also takes the version as an id" do
      step = build({ "op" => "update_version", "id" => version.id, "attributes" => { "effective_date" => "2026-10-30" } }).first

      expect(step).to include("type" => "Version", "id" => version.id)
    end

    it "refuses a version the project does not have" do
      expect { build({ "op" => "update_version", "version" => "v9.9", "attributes" => {} }) }
        .to raise_error(Assistant::Reasoning::Tools::Refused)
    end
  end

  describe "update_work_package" do
    it "still resolves the work package and the names inside its attributes" do
      step = build({ "op" => "update_work_package", "work_package" => "##{work_package.id}",
                     "attributes" => { "version" => "v1.1", "due_date" => "2026-10-30" } }).first

      expect(step).to include("type" => "WorkPackage", "id" => work_package.id,
                              "attributes" => { "version_id" => version.id, "due_date" => "2026-10-30" })
    end
  end
end
