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

RSpec.describe Assistant::Proactive::Detectors::EstimateChangeEffect do
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

  def raised!(wp, from, to) = event!("work_package.updated", wp, remaining_hours: [from, to])

  it "tells whoever raised the time that the owner cannot finish before the due date, with a later date" do
    wp = create(:work_package, project:, assigned_to: ben, start_date: today, due_date: today + 1, remaining_hours: 10)
    raised!(wp, 4.0, 10.0)

    found = candidates

    expect(found.size).to eq(1)
    expect(found.first).to have_attributes(recipient: lead, subject: wp, channel: "inline")
    expect(found.first.headline).to include("Ben", "2 h")
    option = found.first.options_for(lead).first
    expect(option[:kind]).to eq("reschedule")
    expect(Date.iso8601(option[:steps].first.dig("attributes", "due_date"))).to be > wp.due_date
  end

  it "says nothing when the owner still has room" do
    wp = create(:work_package, project:, assigned_to: ben, start_date: today, due_date: today + 1, remaining_hours: 6)
    raised!(wp, 4.0, 6.0)

    expect(candidates).to be_empty
  end

  it "says nothing when the time went down" do
    wp = create(:work_package, project:, assigned_to: ben, start_date: today, due_date: today + 1, remaining_hours: 10)
    raised!(wp, 14.0, 10.0)

    expect(candidates).to be_empty
  end

  it "says nothing for an estimate the remaining time overrules" do
    wp = create(:work_package, project:, assigned_to: ben, start_date: today, due_date: today + 1, estimated_hours: 20,
                               remaining_hours: 2)
    event!("work_package.updated", wp, estimated_hours: [4.0, 20.0])

    expect(candidates).to be_empty
  end

  context "when the work is in a running sprint" do
    let!(:sprint) { create(:sprint, project:, start_date: Date.new(2026, 10, 12), finish_date: Date.new(2026, 10, 16)) }
    let!(:following) { create(:sprint, project:, start_date: Date.new(2026, 10, 19), finish_date: Date.new(2026, 10, 23)) }

    it "tells how much room the owner has left in the sprint and offers the next sprint" do
      allow(Assistant::Facts::Capacity).to receive(:new)
        .and_return(instance_double(Assistant::Facts::Capacity, hours: 20.0, absences: [], because: "20 h"))
      wp = create(:work_package, project:, sprint:, assigned_to: ben, remaining_hours: 26)
      raised!(wp, 8.0, 26.0)

      found = candidates

      expect(found.size).to eq(1)
      expect(found.first.headline).to include(sprint.name, "-6 h")
      option = found.first.options_for(lead).first
      expect(option).to include(kind: "cut_scope")
      expect(option[:steps].first["attributes"]).to eq("sprint_id" => following.id)
    end
  end
end
