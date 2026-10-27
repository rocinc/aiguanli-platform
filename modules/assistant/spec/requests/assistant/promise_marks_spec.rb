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
require_relative "../../support/intent_helpers"

RSpec.describe "Who said they would do the work, shown on the work package", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:ada) { create(:user, firstname: "Ada", lastname: "A", member_with_roles: { project => role }) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "权限模型", assigned_to: ben) }

  before { Assistant::Membership.ensure_member!(project) }

  def promise!(counterparty: nil, **attributes)
    create_intent(project:, subject: work_package, owner: ben, counterparty:, kind: "commitment", status: "open",
                  quote: "两天内搞定", stated_at: Time.zone.local(2026, 9, 12, 10), **attributes)
  end

  def day = Assistant::Text.day(Date.new(2026, 9, 12))

  def promises = response.parsed_body.css("[data-test-selector='assistant-promise'] .assistant-promises--sentence").map { it.text.squish }

  def read_as(user)
    login_as(user)
    get assistant_work_package_field_aside_path(work_package, field: "date")
  end

  it "is not repeated under the title" do
    promise!(counterparty: ada, said_due_expression: "两天")
    login_as(ada)

    get assistant_work_package_line_path(work_package)

    expect(response.body).to eq(%(<turbo-frame id="assistant-wp-line-frame"></turbo-frame>))
  end

  it "tells the one who promised that it is them" do
    promise!(said_due_expression: "两天")

    read_as(ben)

    expect(promises).to eq([I18n.t("assistant.marks.promise.commitment", name: I18n.t("assistant.marks.you"), day:, said: "两天")])
  end

  it "tells the one who waits for it who said it, and when" do
    promise!(counterparty: ada, said_due_expression: "两天")

    read_as(ada)

    expect(promises).to eq([I18n.t("assistant.marks.promise.commitment", name: "Ben B", day:, said: "两天")])
  end

  it "says only that it was promised when no time was named" do
    promise!(counterparty: ada)

    read_as(ada)

    expect(promises).to eq([I18n.t("assistant.marks.promise_plain.commitment", name: "Ben B", day:)])
  end

  it "shows nobody else anything: the due date is all they see" do
    promise!(counterparty: ada, said_due_expression: "两天")

    read_as(sam)

    expect(response.body).to eq(%(<turbo-frame id="assistant-wp-field-aside-date"></turbo-frame>))
  end

  it "leaves out what is finished, withdrawn, or only a request to someone" do
    promise!(counterparty: ada, status: "done")
    promise!(counterparty: ada, status: "withdrawn")
    promise!(counterparty: ada, strength: "requested")

    read_as(ada)

    expect(promises).to be_empty
  end

  it "leaves out a promise whose original words the reader cannot open" do
    elsewhere = create(:project, public: false, enabled_module_names: %w[work_package_tracking])
    other = create(:work_package, project: elsewhere)
    other.add_journal(user: ben, notes: "两天内搞定")
    other.save!(validate: false)
    promise!(counterparty: ada, source: other.journals.reload.last, said_due_expression: "两天")

    read_as(ada)

    expect(promises).to be_empty
  end

  it "does not take room in the notice line" do
    promise!(counterparty: ada, said_due_expression: "两天")

    read_as(ada)

    expect(response.parsed_body.css("[data-test-selector='assistant-object-line']")).to be_empty
  end
end
