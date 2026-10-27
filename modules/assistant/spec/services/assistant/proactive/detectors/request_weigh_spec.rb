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

RSpec.describe Assistant::Proactive::Detectors::RequestWeigh do
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
  let(:estimate) { instance_double(Assistant::Facts::Estimate, hours: 6.0, sufficient?: true, because: "usually 6 h") }

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

  before { allow(Assistant::Facts::Estimate).to receive(:new).and_return(estimate) }

  def request!(due: Date.new(2026, 10, 15))
    wp = create(:work_package, project:, subject: "Full text search")
    create_intent(project:, subject: wp, owner: ben, counterparty: lead, strength: "requested", title: "验收全文检索",
                  quote: "能周三前帮忙验收一下吗", said_due_on: due)
    wp
  end

  def busy_ben!
    create(:work_package, project:, assigned_to: ben, start_date: today, due_date: today + 1, remaining_hours: 5)
  end

  it "tells the person asked what saying yes by the date costs, with a date that fits and someone with room" do
    create(:work_package, project:, assigned_to: quinn)
    busy_ben!
    wp = request!

    found = candidates

    expect(found.size).to eq(1)
    expect(found.first).to have_attributes(recipient: ben, subject: wp, channel: "inline", nature: :decision, waiting: lead)
    expect(found.first.facts).to include(need: 6.0, over: 3.0)
    options = found.first.options_for(ben)
    expect(options.map { it[:kind] }).to eq(%w[renegotiate request_alternate])
    expect(options.first[:reply_draft]).to include("10/16")
    expect(options.last[:reply_draft]).to include("Quinn")
    ask = options.last[:steps].sole
    expect(ask).to include("op" => "comment", "as" => "person", "id" => wp.id)
    expect(ask.dig("attributes", "notes")).to include("Quinn").and include("10/15")
  end

  it "says nothing when the time left covers the request" do
    request!

    expect(candidates).to be_empty
  end

  it "says nothing without an effort known from time logged here" do
    busy_ben!
    request!
    allow(estimate).to receive(:sufficient?).and_return(false)

    expect(candidates).to be_empty
  end

  it "does not invent a date when none was named and the work has no due date" do
    busy_ben!
    request!(due: nil)

    expect(candidates).to be_empty
  end

  it "takes the due date of the work when the request names none" do
    busy_ben!
    request!(due: nil).update_column(:due_date, Date.new(2026, 10, 15))

    expect(candidates.first.headline).to include("10/15")
  end

  it "leaves a request that has been answered alone" do
    busy_ben!
    request!
    Assistant::Intent.update_all(status: "done")

    expect(candidates).to be_empty
  end
end
