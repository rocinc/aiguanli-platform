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

RSpec.describe Assistant::Appraisals::Profile do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant backlogs]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned]) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:sam) { create(:user, firstname: "Sam", lastname: "S", member_with_roles: { project => role }) }
  shared_let(:closed) { create(:closed_status) }
  shared_let(:open_status) { create(:default_status) }
  shared_let(:bug) { create(:type, name: "Bug") }

  let(:from) { Date.new(2026, 7, 1) }
  let(:to) { Date.new(2026, 9, 30) }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    Assistant::Facts.reset!
  end

  def at(time, &)
    travel_to(time, &)
  end

  def profile = Assistant::Appraisals::Team.new(project:, from:, to:).profile(ben, viewer: sam)

  def closed_on(wp, date) = at(date.to_time + 10.hours) { wp.update!(status: closed) }

  it "takes blocked time off lateness and counts a date moved early as kept (05 §3)" do
    blocker = at(Time.zone.local(2026, 7, 1, 9)) { create(:work_package, project:, assigned_to: sam, status: open_status) }
    blocked = at(Time.zone.local(2026, 7, 1, 9)) do
      create(:work_package, project:, assigned_to: ben, start_date: Date.new(2026, 7, 6), due_date: Date.new(2026, 7, 10))
    end
    create(:relation, from: blocker, to: blocked, relation_type: "blocks")
    closed_on(blocker, Date.new(2026, 7, 14))
    closed_on(blocked, Date.new(2026, 7, 15))

    moved = at(Time.zone.local(2026, 7, 1, 9)) { create(:work_package, project:, assigned_to: ben, due_date: Date.new(2026, 8, 7)) }
    at(Time.zone.local(2026, 8, 3, 9)) { moved.update!(due_date: Date.new(2026, 8, 12)) }
    closed_on(moved, Date.new(2026, 8, 11))

    plain = at(Time.zone.local(2026, 7, 1, 9)) { create(:work_package, project:, assigned_to: ben, due_date: Date.new(2026, 9, 4)) }
    closed_on(plain, Date.new(2026, 9, 3))

    delivery = profile.to_h["dimensions"]["delivery"]

    expect(delivery).to include("value" => 100, "sample" => 3, "insufficient" => false)
    expect(delivery["uncorrected"]).to be < 100
    expect(profile.to_h["situation"]).to include("blocked_working_days" => be_positive, "renegotiated_early" => 1)
  end

  it "says there is not enough data instead of a number, and leaves the member out of the ranking" do
    wp = at(Time.zone.local(2026, 7, 1, 9)) { create(:work_package, project:, assigned_to: ben, due_date: Date.new(2026, 7, 3)) }
    closed_on(wp, Date.new(2026, 7, 10))

    team = Assistant::Appraisals::Team.new(project:, from:, to:)

    expect(team.profile(ben).to_h["dimensions"]["delivery"]).to include("value" => nil, "insufficient" => true)
    expect(team.ranking["delivery"]["not_enough_data"]).to include(ben.name)
  end

  it "counts defects linked to their work, how fast they answer, context switches and the trend (05 §2)" do
    wp = at(Time.zone.local(2026, 8, 3, 9)) { create(:work_package, project:, assigned_to: ben, subject: "Export") }
    closed_on(wp, Date.new(2026, 8, 5))
    defect = at(Time.zone.local(2026, 8, 20, 9)) { create(:work_package, project:, type: bug, subject: "Export broken") }
    create(:relation, from: wp, to: defect, relation_type: "relates")

    question = at(Time.zone.local(2026, 8, 10, 9)) do
      create_intent(project:, subject: wp, owner: sam, counterparty: ben, kind: "question", status: "answered",
                    title: "Which format?", quote: "Which format?", stated_at: Time.zone.local(2026, 8, 10, 9))
    end
    wp.add_journal(user: ben, notes: "PDF and Markdown.")
    wp.save!(validate: false)
    answer = wp.journals.reload.last
    answer.update_column(:created_at, Time.zone.local(2026, 8, 12, 9))
    question.update!(answered_by: answer)

    others = Array.new(3) { create(:work_package, project:, assigned_to: ben) }
    others.each { create(:time_entry, project:, entity: it, user: ben, hours: 1, spent_on: Date.new(2026, 8, 18)) }

    dims = profile.to_h["dimensions"]

    expect(dims["quality"]).to include("defects" => 1)
    expect(dims["quality"]["evidence"]).to include("##{defect.id} Export broken")
    expect(dims["collaboration"]).to include("response_working_days" => 2)
    expect(dims["load"]).to include("switch_days" => 1)
    expect(dims["delivery"]).to have_key("previous")
    expect(dims["knowledge"]).to include("helped_newcomers" => 0)
  end
end
