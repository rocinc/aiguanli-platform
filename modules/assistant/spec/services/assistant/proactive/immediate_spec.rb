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
require_relative "../../../support/intent_helpers"

RSpec.describe Assistant::Proactive::Immediate, with_settings: { journal_aggregation_time_minutes: 0 } do
  shared_let(:project) do
    create(:project, enabled_module_names: %w[work_package_tracking assistant backlogs])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:quinn) { create(:user, firstname: "Quinn", lastname: "Q", member_with_roles: { project => role }) }

  let(:today) { Date.current }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
    allow(Assistant::Facts::Capacity).to receive(:new) do |_user, from, to|
      instance_double(Assistant::Facts::Capacity, hours: (from.to_date..to.to_date).count { !it.saturday? && !it.sunday? } * 4.0,
                                                  absences: [], because: "4 h a day")
    end
    Assistant::Facts.reset!
    Assistant::Membership.ensure_member!(project)
    User.current = lead
  end

  def update!(work_package, **attributes)
    result = WorkPackages::UpdateService.new(user: lead, model: WorkPackage.find(work_package.id)).call(**attributes)
    expect(result).to be_success
  end

  def signals(detector) = Assistant::Signal.where(recipient: lead, detector:)

  def busy_quinn!(hours)
    create(:work_package, project:, subject: "Quinn busy #{SecureRandom.hex(3)}", assigned_to: quinn, start_date: today,
                          due_date: today + 1, remaining_hours: hours)
  end

  def work_package_of_ben
    create(:work_package, project:, subject: "Ben owns #{SecureRandom.hex(3)}", assigned_to: ben, start_date: today,
                          due_date: today + 3, remaining_hours: 4)
  end

  it "tells whoever handed the work over right after the save, and keeps it off the object line meanwhile" do
    busy_quinn!(40)
    work_package = work_package_of_ben

    update!(work_package, assigned_to_id: quinn.id)

    signal = signals("assignee_change_load").sole
    expect(signal).to have_attributes(channel: "inline", state: "pending", subject: work_package)
    expect(described_class.fresh_for(work_package, lead)).to eq(signal)
    expect(Assistant::ObjectLineComponent.signals_for(work_package, lead)).to be_empty
  end

  it "leaves the sweep nothing to say again" do
    busy_quinn!(40)
    update!(work_package_of_ben, assigned_to_id: quinn.id)

    Assistant::Proactive::Engine.new(project, detectors: [Assistant::Proactive::Detectors::AssigneeChangeLoad],
                                              writer: described_class::Plain).sweep

    expect(signals("assignee_change_load").count).to eq(1)
  end

  it "shows the same line on the object page once the moment has passed" do
    busy_quinn!(40)
    work_package = work_package_of_ben
    update!(work_package, assigned_to_id: quinn.id)

    travel_to(described_class::ASIDE_FOR.from_now + 1.minute) do
      expect(described_class.fresh_for(work_package, lead)).to be_nil
      expect(Assistant::ObjectLineComponent.signals_for(work_package, lead).size).to eq(1)
    end
  end

  it "says nothing when the new owner has room" do
    update!(work_package_of_ben, assigned_to_id: quinn.id)

    expect(signals("assignee_change_load")).to be_empty
  end

  it "says nothing to someone who asked not to hear about it" do
    Assistant::Preference.for(lead).mute!("assignee_change_load")
    busy_quinn!(40)

    update!(work_package_of_ben, assigned_to_id: quinn.id)

    expect(signals("assignee_change_load")).to be_empty
  end

  it "names what stays open when a work package is closed" do
    closed = create(:status, is_closed: true)
    parent = create(:work_package, project:, subject: "Parent #{SecureRandom.hex(3)}", assigned_to: ben)
    create(:work_package, project:, subject: "Child #{SecureRandom.hex(3)}", parent:, assigned_to: ben)
    create(:workflow, role:, type: parent.type, old_status: parent.status, new_status: closed)
    Assistant::Facts.reset!

    update!(parent, status_id: closed.id)

    expect(signals("close_with_open_children").sole.headline).to include("##{parent.id}")
  end

  describe ".weigh_requests" do
    let(:estimate) { instance_double(Assistant::Facts::Estimate, hours: 6.0, sufficient?: true, because: "usually 6 h") }

    before { allow(Assistant::Facts::Estimate).to receive(:new).and_return(estimate) }

    def request!
      create(:work_package, project:, subject: "Full text #{SecureRandom.hex(3)}", assigned_to: ben, start_date: today,
                            due_date: today + 1, remaining_hours: 5)
      work_package = create(:work_package, project:, subject: "Acceptance #{SecureRandom.hex(3)}")
      create_intent(project:, subject: work_package, owner: ben, counterparty: lead, strength: "requested", title: "验收全文检索",
                    quote: "能明天前帮忙验收一下吗", said_due_on: today + 1)
    end

    it "tells the person asked what saying yes costs, under the comment that asked, not on the page header" do
      request = request!

      described_class.weigh_requests([request])

      signal = Assistant::Signal.where(recipient: ben, detector: "request_weigh").sole
      expect(signal.payload["source_gid"]).to eq(request.source.to_gid.to_s)
      expect(Assistant::ObjectLineComponent.signals_for(request.subject, ben)).to be_empty
    end

    it "ignores requests that are not waiting for an answer" do
      request = request!
      request.update!(strength: "firm")

      described_class.weigh_requests([request])

      expect(Assistant::Signal.where(detector: "request_weigh")).to be_empty
    end
  end
end
