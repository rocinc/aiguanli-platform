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

RSpec.describe Assistant::DateAside do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:lead) { create(:user, member_with_roles: { project => role }) }
  shared_let(:version) { create(:version, project:, effective_date: Date.current + 1) }

  let(:work_package) { create(:work_package, project:, start_date: Date.current, due_date: Date.current + 10) }

  before do
    Assistant::Membership.ensure_member!(project)
    WorkPackageVersion.create!(work_package:, version:, kind: "target")
  end

  def the_event
    Assistant::Event.create!(kind: "work_package.updated", subject: work_package, project:, actor: lead,
                             changes_made: { "due_date" => [(Date.current + 3).iso8601, (Date.current + 10).iso8601] },
                             journal: work_package.journals.last, created_at: Time.current)
  end

  def cascades = Assistant::Proactive::Detectors::DateChangeCascade.new(project, since: 1.hour.ago).candidates

  def shown_to(user)
    aside = described_class.new(work_package, user)
    work_package.due_date = Date.current + 10
    allow(aside).to receive(:compute).and_return(
      described_class::Result.new(shifts: [described_class::Shift.new(id: 1, subject: "x", days: 3)], slips: [], overlaps: [])
    )
    allow(work_package).to receive(:start_date_changed?).and_return(true)
    aside.call
  end

  it "tells the person after the save what the date dialog has not already said" do
    the_event

    expect(cascades.map(&:recipient)).to eq([lead])
  end

  it "leaves out of the save-time notice what the dialog said while the person was deciding" do
    the_event
    shown_to(lead)

    expect(cascades).to be_empty
  end

  it "still tells someone who did not see the dialog's note" do
    the_event
    shown_to(create(:user, member_with_roles: { project => role }))

    expect(cascades.map(&:recipient)).to eq([lead])
  end
end
