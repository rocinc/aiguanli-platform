# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

# 02 §2.1: dependencies, splits, time off, time spent, risks and knowledge.
RSpec.describe Assistant::Understanding::Signals do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant wiki costs]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_packages manage_subtasks
                                          manage_work_package_relations log_own_time log_time view_time_entries
                                          view_wiki_pages edit_wiki_pages use_assistant])
  end
  shared_let(:ben) { create(:user, firstname: "Ben", member_with_roles: { project => role }) }
  shared_let(:sam) { create(:user, firstname: "Sam", member_with_roles: { project => role }) }
  shared_let(:wiki) { project.wiki || create(:wiki, project:) }
  shared_let(:activity) { create(:time_entry_activity, is_default: true) }
  shared_let(:api) { create(:work_package, project:, subject: "Search API", assigned_to: ben) }
  shared_let(:ui) { create(:work_package, project:, subject: "Search UI", assigned_to: ben) }

  before { Assistant::Membership.ensure_member!(project) }

  def comment(text, by: ben)
    ui.add_journal(user: by, notes: text)
    ui.save_journals
    ui.journals.reload.last
  end

  def signal(type, quote, **rest) = { "type" => type, "quote" => quote, "certainty" => "certain", **rest.stringify_keys }

  it "logs the speaker's own time at once, and offers a dependency on a named work package to its owner" do
    journal = comment("排查花了三小时，等 ##{api.id} 好了再开始联调")

    actions = described_class.for(journal, [signal("time_spent", "排查花了三小时", target: "this", hours: 3),
                                            signal("dependency", "等 ##{api.id} 好了再开始联调", target: "this", on: "##{api.id}")])

    expect(actions.map(&:status)).to eq(%w[executed proposed])
    expect(TimeEntry.find_by(entity: ui, user: ben)).to have_attributes(hours: 3.0)
    expect(Relation.where(from: ui, to: api)).to be_empty
    expect(Assistant::Signal.find_by(detector: "said_dependency")).to have_attributes(recipient: ben)
  end

  it "drops what it cannot pin down: an unnamed work package, someone else's time off" do
    journal = comment("Sam 下周不在，这个依赖另一个接口", by: ben)

    actions = described_class.for(journal, [signal("time_off", "Sam 下周不在", member_id: sam.id,
                                                                            from: { "kind" => "working_days", "value" => 5 }),
                                            signal("dependency", "这个依赖另一个接口", target: "this", on: "another")])

    expect(actions).to be_empty
  end

  it "keeps a risk and a term on the project's pages, once" do
    journal = comment("接口文档一直没给，可能拖期。另外 owner_id 是旧版的负责人字段")
    raw = [signal("risk", "接口文档一直没给", target: "this", title: "接口文档迟迟未交付"),
           signal("knowledge", "owner_id 是旧版的负责人字段", term: "owner_id", explanation: "旧版的负责人字段")]

    actions = described_class.for(journal, raw)
    actions.each { Assistant::Decisions.new(it, user: it.on_behalf_of).approve }

    expect(wiki.reload.find_page("Risk register").text).to include("##{ui.id} 接口文档迟迟未交付", "接口文档一直没给")
    expect(wiki.find_page("Glossary").text).to include("**owner_id**")
    expect(described_class.for(comment("接口文档一直没给，可能拖期。另外 owner_id 是旧版的负责人字段"), raw)).to be_empty
  end

  it "creates neither the action nor the signal for a kind the decider muted, and again once it is back on" do
    journal = comment("等 ##{api.id} 好了再开始联调")
    raw = [signal("dependency", "等 ##{api.id} 好了再开始联调", target: "this", on: "##{api.id}")]
    preference = Assistant::Preference.for(ben)
    preference.mute!("said_dependency")

    expect { described_class.for(journal, raw) }.not_to change { [Assistant::Action.count, Assistant::Signal.count] }

    preference.unmute!("said_dependency")
    described_class.for(journal, raw)
    expect(Assistant::Signal.where(detector: "said_dependency", recipient: ben)).to exist
  end

  it "stays silent for a kind the project turned off" do
    journal = comment("等 ##{api.id} 好了再开始联调")
    Assistant::Preference.for(project).update!(muted_detectors: %w[said_dependency])

    described_class.for(journal, [signal("dependency", "等 ##{api.id} 好了再开始联调", target: "this", on: "##{api.id}")])

    expect(Assistant::Signal.where(detector: "said_dependency")).to be_empty
  end
end
