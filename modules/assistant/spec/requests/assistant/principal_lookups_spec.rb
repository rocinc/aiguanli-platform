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

RSpec.describe "Places that tell principals apart, with the assistant among them" do
  include API::V3::Utilities::PathHelper

  shared_let(:project) { create(:project) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages]) }
  shared_let(:colleague) { create(:user, member_with_roles: { project => role }) }

  let!(:assistant) do
    RequestStore.delete(:assistant_user)
    AssistantUser.instance.tap { Assistant::Membership.ensure_member!(project) }
  end

  describe API::V3::WorkPackages::WorkPackageSqlRepresenter do
    subject(:links) do
      JSON.parse(
        API::V3::Utilities::SqlRepresenterWalker
          .new(WorkPackage.where(id: work_package.id), current_user: colleague, url_query: { select: { "*" => {} } })
          .walk(described_class)
          .to_json
      ).fetch("_links")
    end

    let(:work_package) { create(:work_package, project:, assigned_to: assistant, author: assistant) }

    it "links the assistant as assignee and author like any user" do
      expect(links.fetch("assignee")).to eq("href" => api_v3_paths.user(assistant.id), "title" => assistant.name)
      expect(links.fetch("author")).to eq("href" => api_v3_paths.user(assistant.id), "title" => assistant.name)
    end
  end

  describe Queries::WorkPackages::Filter::PrincipalLoader do
    it "offers the assistant among the users, so that filtering by author or watcher accepts it" do
      expect(described_class.new(project).user_values.pluck(1)).to contain_exactly(colleague.id.to_s, assistant.id.to_s)
    end
  end
end
