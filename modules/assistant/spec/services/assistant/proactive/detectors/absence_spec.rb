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

RSpec.describe "Absence detectors" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant meetings wiki github]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant view_meetings]) }
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }

  let(:now) { Time.zone.local(2026, 10, 14, 15) }
  let(:today) { now.to_date }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
  end

  around { |example| travel_to(now) { example.run } }

  def candidates(detector) = detector.new(project, today:).candidates

  describe Assistant::Proactive::Detectors::MeetingWithoutMinutes do
    let!(:meeting) do
      create(:meeting, project:, author: lead, title: "Planning", start_time: now - 5.hours, duration: 1).tap do |m|
        create(:meeting_agenda_item, meeting: m, title: "Search scope", notes: "Keep full-text search out of 2.0")
      end
    end

    it "offers the host a minutes page built from the agenda" do
      found = candidates(described_class)

      expect(found.size).to eq(1)
      expect(found.first).to have_attributes(recipient: lead, subject: meeting, channel: "inline")
      step = found.first.options_for(lead).first[:steps].first
      expect(step["op"]).to eq("create_wiki_page")
      expect(step["attributes"]["text"]).to include("Search scope", "Keep full-text search out of 2.0")
    end

    it "is quiet once something was written down" do
      create(:meeting_outcome, meeting_agenda_item: meeting.agenda_items.first, notes: "Agreed.")

      expect(candidates(described_class)).to be_empty
    end
  end

  describe Assistant::Proactive::Detectors::ReviewWaiting do
    let!(:wp) { create(:work_package, project:, assigned_to: ben, responsible: lead) }

    it "reminds the accountable, not the author, after two working days" do
      pr = create(:github_pull_request, work_packages: [wp], created_at: Time.zone.local(2026, 10, 9, 10))

      found = candidates(described_class)

      expect(found.size).to eq(1)
      expect(found.first).to have_attributes(recipient: lead, subject: wp)
      expect(found.first.facts).to include(waited_working_days: 3)

      pr.update_columns(created_at: Time.zone.local(2026, 10, 12, 10))
      expect(candidates(described_class)).to be_empty
    end
  end
end
