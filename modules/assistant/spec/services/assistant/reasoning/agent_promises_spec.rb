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

RSpec.describe Assistant::Reasoning::Agent, "promising a button" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search API", assigned_to: sam, due_date: Date.current + 5) }

  let(:steps) do
    [{ "op" => "update_work_package", "work_package" => "##{work_package.id}",
       "attributes" => { "due_date" => (Date.current + 9).iso8601 } }]
  end
  let(:rounds) { [] }
  let(:llm) do
    instance_double(Assistant::Llm).tap do |llm|
      allow(llm).to receive(:chat) { |**| rounds.shift }
    end
  end

  def call(name, arguments) = Assistant::Llm::ToolCall.new(id: "c#{rounds.size}", name:, arguments:)

  def reply(content, *tool_calls) = Assistant::Llm::Reply.new(content:, tool_calls:, finish_reason: "stop", usage: {})

  def run
    described_class.new(user: sam, project:, llm:).run([{ "role" => "user", "content" => "换个办法" }])
  end

  context "when the model previewed and then wrote that there is a button, without proposing" do
    before do
      rounds.push(reply("", call("preview", { "steps" => steps })),
                  reply("预览已经备好，下面有按钮，点确认就行。"))
    end

    it "prepares the previewed change as a held card so the button is really there" do
      result = run

      expect(result.cards).to contain_exactly(a_hash_including("type" => "action"))
      action = Assistant::Action.find(result.cards.first["action_id"])
      expect(action).to have_attributes(status: "proposed", plan: a_hash_including("steps" => a_kind_of(Array)))
      expect(work_package.reload.due_date).to eq(Date.current + 5)
      expect(result.content).to include("下面有按钮")
    end
  end

  context "when nothing was previewed either" do
    before { rounds.push(reply("下面有按钮，点确认就行。")) }

    it "says that nothing is prepared instead of leaving the promise" do
      result = run

      expect(result.cards).to be_empty
      expect(result.content).to end_with(I18n.t("assistant.reasoning.no_buttons"))
    end
  end

  context "when the preview failed and the model still promises a button" do
    before do
      bad = [{ "op" => "update_work_package", "work_package" => "#999999", "attributes" => {} }]
      rounds.push(reply("", call("preview", { "steps" => bad })), reply("下面有按钮。"))
    end

    it "does not prepare anything and says so" do
      result = run

      expect(result.cards).to be_empty
      expect(result.content).to end_with(I18n.t("assistant.reasoning.no_buttons"))
    end
  end

  context "when the model proposed itself" do
    before do
      rounds.push(reply("", call("propose", { "title" => "Move it", "steps" => steps, "hold" => true })),
                  reply("下面有按钮，点确认就行。"))
    end

    it "leaves the answer alone" do
      result = run

      expect(result.cards.size).to eq(1)
      expect(result.content).to eq("下面有按钮，点确认就行。")
      expect(Assistant::Action.count).to eq(1)
    end
  end

  context "when the answer says there is no button" do
    before { rounds.push(reply("这件事没有按钮可点，只是个建议。")) }

    it "adds nothing" do
      result = run

      expect(result.cards).to be_empty
      expect(result.content).to eq("这件事没有按钮可点，只是个建议。")
    end
  end
end
