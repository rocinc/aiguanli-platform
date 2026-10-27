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

RSpec.describe "Flow, calendar and portfolio detectors" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant board_view]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant
                                          add_work_package_comments view_project])
  end
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:doing) { create(:status, name: "Doing") }
  shared_let(:review) { create(:status, name: "Review") }

  let(:now) { Time.zone.local(2026, 10, 14, 10) }
  let(:today) { now.to_date }

  before do
    travel_to(now)
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
    Assistant::Facts.reset!
  end

  after { travel_back }

  def candidates(detector, on: project) = detector.new(on, today:, since: 1.day.ago).candidates

  def entered(wp, status, days_ago)
    travel_to(now - days_ago.days)
    wp.update!(status:)
  ensure
    travel_to(now)
  end

  describe Assistant::Proactive::Detectors::BoardBottleneck do
    it "tells the lead which column holds work far longer than the rest, with the oldest cards" do
      travel_to(now - 30.days)
      stuck = Array.new(2) { create(:work_package, project:, assigned_to: ben) }
      flowing = Array.new(2) { create(:work_package, project:, assigned_to: ben) }
      travel_to(now)
      stuck.each { entered(it, review, 12) }
      flowing.each { entered(it, doing, 1) }

      found = candidates(described_class).sole

      expect(found.recipient).to eq(lead)
      expect(found.facts).to include(status_id: review.id, cards: 2)
      ask = found.options_for(lead).sole[:steps].sole
      expect(ask["op"]).to eq("comment")
      expect(stuck.map(&:id)).to include(ask["id"])
    end
  end

  describe Assistant::Proactive::Detectors::CalendarCrunch do
    it "offers to move work with slack from an overloaded week into a lighter one" do
      allow(Assistant::Facts::Capacity).to receive(:new) { instance_double(Assistant::Facts::Capacity, hours: 40.0, absences: []) }
      monday = today.next_week(:monday)
      create(:work_package, project:, assigned_to: ben, start_date: monday, due_date: monday + 4, remaining_hours: 40)
      movable = create(:work_package, project:, assigned_to: ben, start_date: monday + 2, due_date: monday + 4, remaining_hours: 20)
      allow_any_instance_of(Assistant::Facts::ScheduleGraph).to receive(:slack).and_return(30)

      found = candidates(described_class).find { it.recipient == ben }

      expect(found).to have_attributes(nature: :own)
      step = found.options_for(ben).sole[:steps].sole
      expect(step["id"]).to eq(movable.id)
      expect(Date.parse(step["attributes"]["start_date"])).to be >= monday + 7
    end

    it "still offers a look at the week when nothing can move" do
      allow(Assistant::Facts::Capacity).to receive(:new) { instance_double(Assistant::Facts::Capacity, hours: 40.0, absences: []) }
      monday = today.next_week(:monday)
      create(:work_package, project:, assigned_to: ben, start_date: monday, due_date: monday + 4, remaining_hours: 40)
      create(:work_package, project:, assigned_to: ben, start_date: monday + 2, due_date: monday + 4, remaining_hours: 20)
      allow_any_instance_of(Assistant::Facts::ScheduleGraph).to receive(:slack).and_return(0)

      found = candidates(described_class).find { it.recipient == ben }

      option = found.options_for(ben).sole
      expect(option).to include(kind: "look", steps: [])
      props = JSON.parse(Rack::Utils.parse_query(URI(option[:url]).query)["query_props"])
      expect(props["f"]).to include({ "n" => "assignee", "o" => "=", "v" => [ben.id.to_s] },
                                    { "n" => "dueDate", "o" => "<>d", "v" => [monday.iso8601, (monday + 6).iso8601] })
    end
  end

  describe Assistant::Proactive::Detectors::PortfolioHealth do
    it "tells the portfolio lead which project's status is better than its facts" do
      portfolio = create(:project, workspace_type: "portfolio", enabled_module_names: %w[assistant])
      child = create(:project, parent: portfolio, name: "Quill", status_code: "on_track")
      create(:member, project: child, principal: lead, roles: [role])
      version = create(:version, project: child, effective_date: today + 5)
      create(:work_package, project: child, version:, due_date: today + 15)

      found = candidates(described_class, on: portfolio.reload).sole

      expect(found.recipient).to eq(lead)
      expect(found.facts[:mismatched]).to eq([child.id])
      expect(found.because.first).to include("Quill")
    end
  end
end
