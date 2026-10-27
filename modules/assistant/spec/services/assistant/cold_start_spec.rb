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

RSpec.describe "The first weeks in a project", with_settings: { working_days: [1, 2, 3, 4, 5] } do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:ben) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: ben) }

  let(:arrived) { Time.zone.local(2026, 10, 12, 9) }

  def candidate(channel: nil)
    Assistant::Proactive::Candidate.build(detector: "stalled", fingerprint: "1", recipient: ben, subject: work_package, project:,
                                          nature: :own, impact: { critical_path: true, deadline: true }, channel:,
                                          headline: "Stalled")
  end

  def gate(on, channel: nil) = Assistant::Proactive::Gate.new(candidate(channel:), today: on).call

  def arrive!
    member = Assistant::Membership.ensure_member!(project)
    member.update_columns(created_at: arrived)
  end

  describe Assistant::ColdStart do
    it "lasts through the tenth working day after the assistant joined, and not a day longer" do
      arrive!

      expect(described_class.active?(project, today: Date.new(2026, 10, 23))).to be(true)
      expect(described_class.active?(project, today: Date.new(2026, 10, 26))).to be(false)
    end

    it "does not apply to a project it never joined" do
      Member.where(principal: Assistant.user).delete_all

      expect(described_class.active?(project, today: Date.new(2026, 10, 13))).to be(false)
    end

    it "calls the first seven days a first week, for the assistant or for the person" do
      arrive!
      Member.where(principal: ben).update_all(created_at: arrived - 1.year)

      expect(described_class.first_week?(project, ben, now: arrived + 3.days)).to be(true)
      expect(described_class.first_week?(project, ben, now: arrived + 10.days)).to be(false)
    end
  end

  describe "the gate" do
    before { arrive! }

    it "keeps an interrupt in the pool during the cold start" do
      expect(gate(Date.new(2026, 10, 14))).to have_attributes(pass: false, route: :pool, reasons: ["cold_start"])
    end

    it "lets what shows on the page where the person is working through" do
      expect(gate(Date.new(2026, 10, 14), channel: "inline").reasons).not_to include("cold_start")
    end

    it "runs as the dial says from the eleventh working day" do
      expect(gate(Date.new(2026, 10, 27))).to have_attributes(pass: true, route: :interrupt)
    end
  end

  describe "what was kept back during the cold start" do
    let(:silent_writer) { Struct.new(:candidate, :options) { def call = {} } }
    let(:early) { Time.zone.local(2026, 10, 14, 10) }
    let(:later) { Time.zone.local(2026, 10, 27, 10) }

    def consider(at)
      Assistant::Proactive::Engine.new(project, now: at, today: at.to_date, writer: silent_writer).consider(candidate)
    end

    before { arrive! }

    it "is listed on the scorecard as not said, with the reason" do
      consider(early)

      held = Assistant::Proactive::Scorecard.new(project, user: ben).held

      expect(held.map(&:reason)).to eq(["cold_start"])
      expect(I18n.t("assistant.insights.held_reasons.cold_start", locale: :"zh-CN")).to eq("还在熟悉期，先不打扰你")
    end

    it "is weighed again once the cold start is over, and then told only once" do
      pooled = consider(early)
      expect(pooled).to have_attributes(state: "held")
      expect(consider(early + 1.day)).to be_nil

      released = consider(later)

      expect(released).to have_attributes(state: "pending")
      expect(released.payload["gate"]).not_to include("cold_start")
      expect(Assistant::Signal.where(recipient: ben, detector: "stalled", fingerprint: "1").pluck(:id)).to eq([released.id])
      expect(consider(later + 1.day)).to be_nil
    end
  end
end
