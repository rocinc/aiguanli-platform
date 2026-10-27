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

RSpec.describe "The assistant as a member", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages view_members manage_members use_assistant]) }
  shared_let(:sam) { create(:user, language: "zh-CN", member_with_roles: { project => role }) }
  let(:assistant) { Assistant.user }

  before do
    Assistant::Membership.ensure_member!(project)
    login_as(sam)
  end

  it "has one picture, drawn here, wherever the platform asks for its avatar" do
    get "/api/v3/users/#{assistant.id}"
    expect(JSON.parse(response.body)["avatar"]).to include("/assistant/avatar")

    get "/api/v3/users/#{assistant.id}/avatar"
    expect(response).to redirect_to("/assistant/avatar?theme=light")

    get "/assistant/avatar"
    expect(response.media_type).to eq("image/svg+xml")
    expect(response.body).not_to match(%r{href=|src=})
  end

  it "is listed on the members page under its own role, without an email, a rate or a way to edit it" do
    get project_members_path(project)

    row = response.parsed_body.at_css("tr.assistant_user")
    expect(row.text).to include("AI 助理")
    expect(row.text).not_to include("assistant.invalid")
    expect(row.css("form, [data-members-form-target], action-menu")).to be_empty
    expect(row.at_css("a")["href"]).to eq(project_assistant_desk_path(project))
  end

  it "says in its hover card who it is and who may call it" do
    get hover_card_user_path(assistant)

    expect(response.parsed_body.text).to include("不是真人", "按 a 键")
  end

  it "has no mailbox" do
    mail = Mail.new(to: [User.find(sam.id).mail, assistant.mail], subject: "x", body: "x")
    OpenProject::Assistant::MailGuard.delivering_email(mail)
    expect(mail.to).to eq([sam.mail])

    only_it = Mail.new(to: [assistant.mail], subject: "x", body: "x")
    OpenProject::Assistant::MailGuard.delivering_email(only_it)
    expect(only_it.perform_deliveries).to be(false)
  end
end
