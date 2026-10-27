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
require_relative "../../../support/intent_helpers"

RSpec.describe Assistant::Actions::SourceNote do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages add_work_packages edit_work_packages use_assistant])
  end
  shared_let(:ben) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:) }

  let(:journal) do
    work_package.add_journal(user: ben, notes: "导出得支持 PDF")
    work_package.save!(validate: false)
    work_package.journals.reload.last
  end
  let(:basis) { [Assistant::Basis.for(journal, quote: "导出得支持 PDF").to_h] }
  let(:steps) { [{ "op" => "create_work_package", "attributes" => { "project_id" => project.id, "subject" => "PDF 导出" } }] }

  def description_of(result) = result.first.dig("attributes", "description")

  it "ends the description with where it came from: the words and a link to them" do
    description = description_of(described_class.apply(steps, basis))

    expect(description).to start_with("**#{I18n.t('assistant.source_note.heading')}**")
    expect(description).to include("> 导出得支持 PDF", "/work_packages/#{work_package.id}/activity#comment-#{journal.id}")
  end

  it "keeps what the description already says and adds the section after it" do
    steps.first["attributes"]["description"] = "支持 PDF 和 Word。"

    description = description_of(described_class.apply(steps, basis))

    expect(description).to start_with("支持 PDF 和 Word。\n\n**#{I18n.t('assistant.source_note.heading')}**")
  end

  it "does not say it twice" do
    once = described_class.apply(steps, basis)

    expect(description_of(described_class.apply(once, basis))).to eq(description_of(once))
  end

  it "leaves a work package alone that did not come from anything someone said" do
    from_a_duty = [Assistant::Basis.new(kind: "assistant/duty", gid: "gid://x/Assistant::Duty/1", quote: nil, label: "x").to_h]

    expect(description_of(described_class.apply(steps, from_a_duty))).to be_nil
    expect(description_of(described_class.apply(steps, []))).to be_nil
  end

  it "does not quote a comment only some people may read" do
    journal.update_columns(internal: true)

    expect(description_of(described_class.apply(steps, basis))).to be_nil
  end

  it "only touches steps that create work packages" do
    update = { "op" => "update_work_package", "type" => "WorkPackage", "id" => work_package.id, "attributes" => { "subject" => "x" } }

    expect(described_class.apply([update], basis)).to eq([update])
  end

  it "is what a proposal carries, so the person deciding reads it too" do
    action = Assistant::Actions::Propose.call(kind: "request_draft", title: "PDF 导出", steps:, on_behalf_of: ben, project:,
                                              subject: work_package, basis:, auto_execute: false)

    expect(action.steps.first.dig("attributes", "description")).to include("> 导出得支持 PDF")
  end
end
