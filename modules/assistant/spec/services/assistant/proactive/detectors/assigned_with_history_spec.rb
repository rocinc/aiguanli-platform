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
require_relative "../../../../support/intent_helpers"

RSpec.describe Assistant::Proactive::Detectors::AssignedWithHistory do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:sam) { create(:user, firstname: "Sam", lastname: "S", member_with_roles: { project => role }) }
  shared_let(:quinn) { create(:user, firstname: "Quinn", lastname: "Q", member_with_roles: { project => role }) }

  let(:today) { Date.new(2026, 10, 14) }
  let(:work_package) { create(:work_package, project:, subject: "权限模型", assigned_to: quinn) }

  def candidates = described_class.new(project, today:, since: 1.day.ago).candidates

  def handed_over!(wp = work_package, actor: lead)
    Assistant::Event.create!(kind: "work_package.updated", subject: wp, project:, actor:,
                             changes_made: { "assigned_to_id" => [sam.id, quinn.id] }, created_at: Time.current)
  end

  def say!(wp, user, notes, **attributes)
    wp.add_journal(user:, notes:)
    wp.save!(validate: false)
    create_intent(project:, subject: wp, owner: user, source: wp.journals.reload.last, quote: notes, **attributes)
  end

  it "tells the new owner what is on record, what nobody answered and who knows most, as facts" do
    say!(work_package, sam, "权限定为知识库级和文档级两层", kind: "decision", status: "active", title: "权限定为两层")
    say!(work_package, sam, "管理员能看到所有文档吗", kind: "question", status: "open", title: "管理员能否看全部")
    handed_over!

    found = candidates

    expect(found.size).to eq(1)
    expect(found.first).to have_attributes(recipient: quinn, subject: work_package, channel: "inline")
    facts = I18n.t("assistant.proactive.assigned_with_history.has",
                   list: [I18n.t("assistant.proactive.assigned_with_history.decisions", count: 1),
                          I18n.t("assistant.proactive.assigned_with_history.questions", count: 1)]
                           .join(I18n.t("assistant.proactive.assigned_with_history.join")))
    expect(found.first.headline).to include("##{work_package.id}", facts)
    expect(found.first.because).to include(a_string_including("权限定为两层"), a_string_including("管理员能否看全部"))
  end

  it "offers a link to each thing on record and nothing else" do
    say!(work_package, sam, "权限定为知识库级和文档级两层", kind: "decision", status: "active", title: "权限定为两层")
    handed_over!

    options = candidates.first.options_for(quinn)
    expect(options.map { it[:kind] }).to eq(%w[look])
    expect(options.first[:steps]).to be_empty
    expect(options.first[:url]).to include("/work_packages/#{work_package.id}/activity#comment-")

    say!(work_package, sam, "管理员能看到所有文档吗", kind: "question", status: "open", title: "管理员能否看全部")
    expect(candidates.first.options_for(quinn).size).to eq(2)
  end

  it "offers the discussion itself when there is only a long thread" do
    3.times { |i| say!(work_package, sam, "更新 #{i}", kind: "commitment", title: "更新 #{i}") }
    handed_over!

    options = candidates.first.options_for(quinn)
    expect(options.size).to eq(1)
    expect(options.first[:url]).to end_with("/work_packages/#{work_package.id}/activity")
    expect(candidates.first.because).to include(a_string_including("3"))
  end

  it "keeps the main sentence whole and drops the expert when the sentence would pass 40 characters" do
    I18n.with_locale(:"zh-CN") do
      say!(work_package, sam, "权限定为知识库级和文档级两层", kind: "decision", status: "active", title: "权限定为两层")
      say!(work_package, sam, "管理员能看到所有文档吗", kind: "question", status: "open", title: "管理员能否看全部")
      allow_any_instance_of(Assistant::Facts::Expertise).to receive(:people).and_return(
        [Assistant::Facts::Expertise::Person.new(user: create(:user, firstname: "Fiona", lastname: "Walsh"), score: 3.0, evidence: ["a"])]
      )
      handed_over!

      headline = candidates.first.headline
      expect(headline.length).to be <= 40
      expect(headline).to end_with("没人回答")
    end
  end

  it "stays quiet when the work package has no past" do
    handed_over!(create(:work_package, project:, assigned_to: quinn))

    expect(candidates).to be_empty
  end

  it "says nothing to someone who took it on themselves" do
    say!(work_package, sam, "权限定为两层", kind: "decision", status: "active", title: "权限定为两层")
    handed_over!(actor: quinn)

    expect(candidates).to be_empty
  end
end
