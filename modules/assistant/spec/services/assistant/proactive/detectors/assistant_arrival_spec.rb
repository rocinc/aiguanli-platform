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

RSpec.describe Assistant::Proactive::Detectors::AssistantArrival do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages use_assistant]) }
  shared_let(:lea) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }

  let(:today) { Date.current }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    Assistant::Membership.ensure_member!(project)
  end

  def candidates(on: today) = described_class.new(project, today: on).candidates

  it "greets each member who was there when the assistant arrived, once, on the project overview" do
    found = candidates

    expect(found.map(&:recipient)).to contain_exactly(lea, ben)
    expect(found.first).to have_attributes(subject: project, channel: "inline", nature: :intro, fingerprint: "arrival:#{project.id}")
    expect(found.first.facts).to include(why: "member")
    expect(found.first.because.size).to eq(3)
  end

  it "names who switched the assistant on, and says today only on the day" do
    Assistant::Duty.create!(project:, kind: "onboarding", delegator: lea, scope: {})

    expect(candidates.map(&:recipient)).to eq([ben])
    I18n.with_locale(:"zh-CN") do
      expect(candidates.first.headline).to eq("我是这个项目的 AI 助理，Lea 今天把我加了进来。我能做什么、不会做什么")
      expect(candidates(on: today + 1).first.headline).to match(%r{Lea \d+/\d+ 加了我})
    end
  end

  it "leaves out someone who joined the project after the assistant" do
    late = create(:user, member_with_roles: { project => role })
    Member.find_by(project:, principal: late).update_column(:created_at, 3.days.from_now)

    expect(candidates.map(&:recipient)).not_to include(late)
  end

  it "stops after the first two weeks" do
    expect(candidates(on: today + 15)).to be_empty
  end

  it "says nothing where the assistant is not a member" do
    Assistant::Membership.remove!(project)

    expect(candidates).to be_empty
  end
end
