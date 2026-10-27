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

RSpec.describe "Contradiction detectors" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }

  let(:today) { Date.new(2026, 10, 14) }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
  end

  def candidates(detector) = detector.new(project, today:).candidates

  describe Assistant::Proactive::Detectors::SaidDoneStillOpen do
    let(:wp) { create(:work_package, project:, assigned_to: ben) }

    it "asks whoever said it was done, a working day later, while it is still open" do
      create_intent(project:, subject: wp, owner: ben, status: "done", resolved_at: Time.zone.local(2026, 10, 12, 10))
      wp.update_columns(updated_at: Time.zone.local(2026, 10, 12, 9))

      found = candidates(described_class)

      expect(found.size).to eq(1)
      expect(found.first).to have_attributes(recipient: ben, subject: wp, nature: :own)
      expect(found.first.options_for(ben).map { it[:kind] }).to include("not_yet")
    end

    it "waits a working day" do
      create_intent(project:, subject: wp, owner: ben, status: "done", resolved_at: Time.zone.local(2026, 10, 14, 10))
      wp.update_columns(updated_at: Time.zone.local(2026, 10, 14, 9))

      expect(candidates(described_class)).to be_empty
    end
  end

  describe Assistant::Proactive::Detectors::GreenButSlipping do
    it "offers to mark the project at risk when it says on track and a version would be late" do
      project.update_columns(status_code: Project.status_codes[:on_track])
      version = create(:version, project:, name: "2.0", effective_date: today + 7)
      create(:work_package, project:, version:, due_date: today + 12)

      found = candidates(described_class)

      expect(found.size).to eq(1)
      step = found.first.options_for(lead).first[:steps].first
      expect(step).to include("op" => "update_project_status", "attributes" => include("status_code" => "at_risk"))
      expect(step["attributes"]["status_explanation"]).to include("2.0")
    end
  end

  describe Assistant::Proactive::Detectors::DeferredStillInVersion do
    it "offers to move a work package someone deferred to the next version" do
      current = create(:version, project:, name: "1.4", effective_date: today + 10)
      later = create(:version, project:, name: "1.5", effective_date: today + 40)
      wp = create(:work_package, project:, version: current)
      create_intent(project:, subject: wp, owner: ben, kind: "deferral", quote: "下版再做",
                    due_anchor: later, said_due_on: later.effective_date)

      found = candidates(described_class)

      expect(found.size).to eq(1)
      expect(found.first.recipient).to eq(ben)
      expect(found.first.options_for(ben).first[:steps].first["attributes"]).to eq("version_id" => later.id)
    end
  end
end
