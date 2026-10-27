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

require "spec_helper"
require_relative "../../../../support/intent_helpers"

RSpec.describe "Opportunity detectors" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant wiki]) }
  shared_let(:other_project) { create(:project, name: "Scribe", enabled_module_names: %w[work_package_tracking]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant
                                          add_work_package_comments manage_work_package_relations view_wiki_pages])
  end
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role, other_project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role, other_project => role }) }
  shared_let(:viewer) { create(:project_role, permissions: %i[view_work_packages]) }
  shared_let(:quinn) do
    create(:user, firstname: "Quinn", lastname: "Q", member_with_roles: { project => role, other_project => viewer })
  end
  shared_let(:mia) { create(:user, firstname: "Mia", lastname: "M", member_with_roles: { other_project => role }) }
  shared_let(:closed) { create(:closed_status) }

  let(:today) { Date.current }

  before do
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
    Assistant::Facts.reset!
  end

  def candidates(detector) = detector.new(project, today:, since: 1.day.ago).candidates

  describe Assistant::Proactive::Detectors::CrossProjectReuse do
    it "shows on new work that another project finished the same thing, and who did it" do
      done = create(:work_package, project: other_project, subject: "扫描件 OCR 识别", assigned_to: mia, status: closed)
      wp = create(:work_package, project:, subject: "扫描件 OCR 识别方案", assigned_to: ben)
      Assistant::Event.create!(kind: "work_package.created", subject: wp, project:, actor: lead, changes_made: {},
                               created_at: Time.current)

      found = candidates(described_class).sole

      expect(found).to have_attributes(recipient: ben, subject: wp, channel: "inline", nature: :opportunity)
      expect(found.because.join).to include("##{done.id}", "Mia M")
      ask = found.options_for(ben).find { it[:kind] == "ask_elsewhere" }[:steps].sole
      expect(ask).to include("op" => "comment", "id" => done.id)
    end
  end

  describe Assistant::Proactive::Detectors::Overlap do
    it "tells each of the two, on their own work package, when they work on what reads like the same thing" do
      one = create(:work_package, project:, subject: "导出 PDF 页码", assigned_to: ben)
      other = create(:work_package, project:, subject: "PDF 导出页码", assigned_to: quinn)
      create(:work_package, project:, subject: "登录页改版", assigned_to: quinn)

      found = candidates(described_class)

      expect(found.map { [it.recipient, it.subject, it.channel] })
        .to contain_exactly([ben, one, "inline"], [quinn, other, "inline"])
      steps = found.find { it.recipient == ben }.options_for(ben).sole[:steps]
      expect(steps.first["attributes"]).to include("relation_type" => "relates")
      expect([steps.first["attributes"]["from_id"], steps.first["attributes"]["to_id"]]).to contain_exactly(one.id, other.id)
    end

    it "is quiet once the two are related" do
      one = create(:work_package, project:, subject: "导出 PDF 页码", assigned_to: ben)
      other = create(:work_package, project:, subject: "PDF 导出页码", assigned_to: quinn)
      create(:relation, from: one, to: other, relation_type: "relates")

      expect(candidates(described_class)).to be_empty
    end
  end

  describe Assistant::Proactive::Detectors::Matchmaker do
    it "introduces whoever asked to someone outside the team who did it, in a project they can see" do
      wp = create(:work_package, project:, subject: "Import", assigned_to: quinn)
      create(:work_package, project: other_project, subject: "扫描件 OCR 识别", assigned_to: mia, status: closed)
      create_intent(project:, subject: wp, owner: quinn, kind: "question", status: "open",
                    title: "扫描件 OCR 识别怎么做", quote: "扫描件 OCR 识别怎么做？", stated_at: 5.days.ago)

      found = candidates(described_class).sole

      expect(found).to have_attributes(recipient: quinn, subject: wp, channel: "inline", nature: :opportunity)
      expect(found.facts).to include(user_id: mia.id)
    end
  end

  describe Assistant::Proactive::Detectors::IdleCapacity do
    it "offers the lead an idea several people raised to someone with room who knows the subject" do
      allow(Assistant::Facts::Capacity).to receive(:new).and_return(instance_double(Assistant::Facts::Capacity, hours: 40.0))
      create(:work_package, project:, subject: "短文本召回率评测", assigned_to: quinn, status: closed)
      idea = Assistant::Idea.create!(project:, title: "短文本召回率改进")
      [ben, lead].each do |user|
        journal = create(:work_package_journal, user:, notes: "要是短文本召回率能更好就好了")
        idea.mentions.create!(speaker: user, source: journal, quote: "要是短文本召回率能更好就好了", said_at: Time.current)
      end

      found = candidates(described_class).find { it.facts[:user_id] == quinn.id }

      expect(found).to have_attributes(recipient: lead, channel: "brief")
      step = found.options_for(lead).sole[:steps].sole
      expect(step["attributes"]).to include("assigned_to_id" => quinn.id, "subject" => "短文本召回率改进")
    end
  end
end
