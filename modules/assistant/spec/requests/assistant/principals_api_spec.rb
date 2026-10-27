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
require "rack/test"

RSpec.describe "API v3 principals with the assistant" do
  include Rack::Test::Methods
  include API::V3::Utilities::PathHelper

  shared_let(:project) { create(:project) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages]) }
  shared_let(:colleague) { create(:user, member_with_roles: { project => role }, firstname: "Ada", lastname: "Nakamura") }
  let!(:assistant) do
    RequestStore.delete(:assistant_user)
    AssistantUser.instance.tap { Assistant::Membership.ensure_member!(project) }
  end

  let(:filters) do
    [{ "status" => { "operator" => "!", "values" => ["3"] } },
     { "member" => { "operator" => "=", "values" => [project.id.to_s] } },
     { "type" => { "operator" => "=", "values" => %w[User Group AssistantUser] } }]
  end
  let(:select) { "elements/_type,elements/id,elements/name" }
  let(:elements) { JSON.parse(last_response.body).dig("_embedded", "elements") }

  current_user { colleague }

  before do
    get api_v3_paths.path_for(:principals, filters:, sort_by: { name: :asc }, select:)
  end

  it "renders the assistant like any other user, never as null" do
    expect(last_response).to have_http_status(:ok)
    expect(elements).to all(be_a(Hash))
    expect(elements.pluck("id")).to contain_exactly(colleague.id, assistant.id)
    expect(elements.pluck("_type")).to all(eq("User"))
  end

  context "without a select" do
    let(:select) { nil }

    it "renders the assistant as a user as well" do
      expect(elements).to all(be_a(Hash))
      expect(elements.pluck("id")).to include(assistant.id)
    end
  end

  context "when asking for colleagues only" do
    let(:filters) do
      super().tap { it.last["type"]["values"] = %w[User Group] }
    end

    it "leaves the assistant out" do
      expect(elements.pluck("id")).to eq([colleague.id])
    end
  end
end
