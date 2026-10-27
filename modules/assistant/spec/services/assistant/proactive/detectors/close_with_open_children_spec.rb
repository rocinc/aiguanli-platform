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

RSpec.describe Assistant::Proactive::Detectors::CloseWithOpenChildren do
  shared_let(:project) do
    create(:project, enabled_module_names: %w[work_package_tracking assistant backlogs])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:quinn) { create(:user, firstname: "Quinn", lastname: "Q", member_with_roles: { project => role }) }

  let(:today) { Date.new(2026, 10, 14) }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
    allow(Assistant::Facts::Capacity).to receive(:new) do |_user, from, to|
      instance_double(Assistant::Facts::Capacity, hours: (from.to_date..to.to_date).count { !it.saturday? && !it.sunday? } * 4.0,
                                                  absences: [], because: "4 h a day")
    end
    Assistant::Facts.reset!
  end

  def candidates = described_class.new(project, today:, since: 1.day.ago).candidates

  def event!(kind, subject, actor: lead, **changes)
    Assistant::Event.create!(kind:, subject:, project:, actor:, changes_made: changes.transform_keys(&:to_s),
                             created_at: Time.current)
  end

  shared_let(:open_status) { create(:status, name: "In progress", is_closed: false) }
  shared_let(:closed_status) { create(:status, name: "Closed", is_closed: true) }

  def closed_parent!
    parent = create(:work_package, project:, status: closed_status)
    event!("work_package.updated", parent, status_id: [open_status.id, closed_status.id])
    parent
  end

  it "lists what is left open and offers to reopen or close the sub-tasks too" do
    parent = closed_parent!
    child = create(:work_package, project:, parent:, status: open_status)
    create_intent(project:, subject: parent, owner: ben, kind: "question", title: "Which search engine?", quote: "which one?")

    found = candidates

    expect(found.size).to eq(1)
    expect(found.first).to have_attributes(recipient: lead, subject: parent, channel: "inline")
    expect(found.first.headline).to include("##{parent.id}", "1 sub-task", "1 question")
    options = found.first.options_for(lead)
    expect(options.map { it[:kind] }).to eq(%w[reopen_work close_children])
    expect(options.first[:steps].first["attributes"]).to eq("status_id" => open_status.id)
    expect(options.last[:steps].map { it["id"] }).to eq([child.id])
  end

  it "says nothing when everything under it is done" do
    parent = closed_parent!
    create(:work_package, project:, parent:, status: closed_status)

    expect(candidates).to be_empty
  end

  it "says nothing for a change that did not close anything" do
    wp = create(:work_package, project:, status: open_status)
    create(:work_package, project:, parent: wp, status: open_status)
    event!("work_package.updated", wp, status_id: [closed_status.id, open_status.id])

    expect(candidates).to be_empty
  end
end
