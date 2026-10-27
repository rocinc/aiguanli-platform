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

RSpec.describe Assistant::Proactive::Detectors::AssigneeChangeLoad do
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

  def handed_over!(remaining: 4)
    wp = create(:work_package, project:, assigned_to: quinn, start_date: today, due_date: today + 1, remaining_hours: remaining)
    event!("work_package.updated", wp, assigned_to_id: [ben.id, quinn.id])
    wp
  end

  def finished_work!(user) = create(:work_package, project:, assigned_to: user, status: create(:closed_status))

  def busy_quinn!(hours)
    create(:work_package, project:, assigned_to: quinn, start_date: today, due_date: today + 1, remaining_hours: hours)
  end

  it "tells whoever handed work over that the new owner is over until it is due, with ways out" do
    finished_work!(lead)
    busy_quinn!(8)
    wp = handed_over!

    found = candidates

    expect(found.size).to eq(1)
    expect(found.first).to have_attributes(recipient: lead, subject: wp, channel: "inline")
    expect(found.first.because.first).to include("Quinn", "4 h")
    expect(found.first.options_for(lead).map { it[:kind] }).to eq(%w[revert_assignee reassign])
  end

  it "does not offer someone who has only planned, or the system administrator, as the one with room" do
    create(:user, firstname: "Ada", lastname: "P", member_with_roles: { project => role })
    create(:admin, member_with_roles: { project => role })
    finished_work!(lead)
    busy_quinn!(8)
    handed_over!

    options = candidates.first.options_for(lead)

    label = options.find { it[:kind] == "reassign" }[:label]
    expect(label).to include("Lea")
    expect(label).not_to include("Ada")
  end

  it "also passes on a promise the previous owner made" do
    busy_quinn!(8)
    wp = handed_over!
    create_intent(project:, subject: wp, owner: ben, counterparty: lead, title: "给 Sam 联调")

    options = candidates.first.options_for(lead)

    expect(options.map { it[:kind] }).to include("handover_promise")
    expect(options.find { it[:kind] == "handover_promise" }[:steps].first.dig("attributes", "notes")).to include("给 Sam 联调")
  end

  it "speaks of the promise alone when the new owner has room" do
    wp = handed_over!
    create_intent(project:, subject: wp, owner: ben, counterparty: lead, title: "给 Sam 联调")

    found = candidates

    expect(found.size).to eq(1)
    expect(found.first.headline).to include("Ben")
    expect(found.first.options_for(lead).map { it[:kind] }).to eq(%w[revert_assignee handover_promise])
  end

  it "says nothing when the new owner has room and nothing was promised" do
    handed_over!

    expect(candidates).to be_empty
  end

  it "says nothing when the change was undone in the meantime" do
    busy_quinn!(8)
    wp = handed_over!
    wp.update_column(:assigned_to_id, ben.id)

    expect(candidates).to be_empty
  end
end
