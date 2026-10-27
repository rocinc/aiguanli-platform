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

RSpec.describe "A proposal waiting for someone is theirs alone", type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant])
  end
  shared_let(:fiona) { create(:user, firstname: "Fiona", lastname: "Walsh", member_with_roles: { project => role }) }
  shared_let(:sam) { create(:user, firstname: "Sam", lastname: "Lee", member_with_roles: { project => role }) }
  shared_let(:admin) { create(:admin) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: fiona, subject: "Downgrade entitlements") }

  let!(:action) do
    Assistant::Actions::Propose.call(
      kind: "reschedule", title: "Move #{work_package.id} to Friday", on_behalf_of: fiona, project:, subject: work_package,
      steps: [{ op: "update_work_package", type: "WorkPackage", id: work_package.id, attributes: { due_date: "2026-10-16" } }],
      auto_execute: false
    )
  end

  before { Assistant::Membership.ensure_member!(project) }

  describe Assistant::Action do
    it "is seen and decided by the person it is for only" do
      expect(action.visible_to?(fiona)).to be(true)
      expect(action.decidable_by?(fiona)).to be(true)

      [sam, admin].each do |other|
        expect(action.visible_to?(other)).to be(false)
        expect(action.decidable_by?(other)).to be(false)
      end
    end

    it "stays a fact for everyone once it has been done" do
      action.update!(status: "executed", executed_at: Time.current, decided_by: fiona)

      expect(action.visible_to?(sam)).to be(true)
    end

    it "is open to those who may decide it when it is not for anyone" do
      action.update!(on_behalf_of: nil)

      expect(action.visible_to?(sam)).to be(true)
      expect(action.decidable_by?(sam)).to be(true)
    end
  end

  describe Assistant::Surface do
    it "offers the proposal to the person it is for, not to others on the same object" do
      expect(described_class.new(subject: work_package, user: fiona).proposals).to eq([action])
      expect(described_class.new(subject: work_package, user: sam).proposals).to be_empty
      expect(described_class.new(subject: work_package, user: sam).count).to eq(0)
    end
  end

  describe Assistant::ObjectLineComponent, type: :component do
    it "says nothing about it on the work package or the project to others" do
      expect(described_class.new(object: work_package, user: sam).render?).to be(false)
      expect(described_class.new(object: project, user: sam).render?).to be(false)
    end

    it "shows it to the person it is for" do
      render_inline(described_class.new(object: work_package, user: fiona))

      expect(page).to have_text("Move #{work_package.id} to Friday")
    end

    it "shows it on the project overview to the person it is for, with the project as subject" do
      action.update!(subject: project)

      expect(described_class.new(object: project, user: fiona).render?).to be(true)
      expect(described_class.new(object: project, user: sam).render?).to be(false)
    end
  end

  describe Assistant::Brief do
    it "does not put it on anyone else's day" do
      expect(described_class.new(user: fiona).drafts.map(&:action)).not_to include(action)
      expect(described_class.new(user: sam).done).to be_empty
    end
  end

  describe "the provenance page", :skip_csrf do
    it "is a 404 for others and open to the person it is for" do
      login_as(sam)
      get assistant_action_path(action)
      expect(response).to have_http_status(:not_found)

      login_as(fiona)
      get assistant_action_path(action)
      expect(response).to have_http_status(:ok)
    end
  end
end
