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

RSpec.describe Assistant::Duties::Defaults do
  shared_let(:lead) { create(:user) }

  def enable_assistant(user)
    project = create(:project, enabled_module_names: %w[work_package_tracking])
    User.execute_as(user) { project.enabled_module_names += %w[assistant] }
    project.reload
  end

  it "hands decision log, meeting follow-up and onboarding to whoever switched the assistant on" do
    project = enable_assistant(lead)

    duties = Assistant::Duty.where(project:)
    expect(duties.pluck(:kind)).to contain_exactly("decision_log", "meeting_followup", "onboarding")
    expect(duties.pluck(:delegator_id).uniq).to eq([lead.id])
    expect(duties.find_by(kind: "decision_log").scope).to eq("ceiling" => "draft")
  end

  it "does not hand over twice or overwrite a duty the project already has" do
    project = enable_assistant(lead)
    other = create(:user)
    Assistant::Duty.find_by(project:, kind: "onboarding").update!(delegator: other, active: false)

    described_class.ensure!(project, lead)

    expect(Assistant::Duty.where(project:).count).to eq(3)
    expect(Assistant::Duty.find_by(project:, kind: "onboarding")).to have_attributes(delegator: other, active: false)
  end

  it "hands over nothing when nobody is logged in to switch it on" do
    project = enable_assistant(User.anonymous)

    expect(Assistant::Duty.where(project:)).to be_empty
  end

  it "respects the duties a project allows" do
    project = create(:project, enabled_module_names: %w[work_package_tracking])
    Assistant::Proactive::ProjectSettings.write!(project, duties: %w[onboarding])

    described_class.ensure!(project, lead)

    expect(Assistant::Duty.where(project:).pluck(:kind)).to eq(["onboarding"])
  end
end
