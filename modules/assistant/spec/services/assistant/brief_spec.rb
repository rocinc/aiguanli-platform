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
#++

require "spec_helper"

RSpec.describe Assistant::Brief do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: sam) }

  def signal!(channel, headline, detector: "meeting_unowned")
    Assistant::Signal.create!(detector:, fingerprint: "#{headline}|#{channel}", recipient: sam, project:, subject: work_package,
                              channel:, state: "delivered", deliver_at: 1.hour.ago, score: 20,
                              payload: { "headline" => headline, "options" => [] })
  end

  it "lists what has no place on a page and leaves out what is still alive on one" do
    signal!("inline", "On the page")
    signal!("brief", "On the page")
    kept = signal!("brief", "Only in the brief")

    expect(described_class.new(user: sam).decisions).to eq([kept])
  end

  it "lists the brief signal again once the inline one is gone" do
    inline = signal!("inline", "On the page")
    shown = signal!("brief", "On the page")
    inline.settle!("resolved")

    expect(described_class.new(user: sam).decisions).to eq([shown])
  end

  it "shows a newcomer the onboarding page written for them under what was done, though it was someone else's to publish" do
    lead = create(:user, member_with_roles: { project => role })
    page = Assistant::Action.create!(kind: Assistant::Duties::Onboarding::KIND, title: "Onboarding", tier: "t1", status: "executed",
                                     project:, on_behalf_of: lead, decided_by: lead, subject: sam, executed_at: 1.hour.ago,
                                     preview: { "success" => true, "changes" => [] }, plan: { "steps" => [] })
    other = Assistant::Action.create!(kind: Assistant::Duties::Onboarding::KIND, title: "Onboarding", tier: "t1", status: "executed",
                                      project:, on_behalf_of: lead, decided_by: lead, subject: lead, executed_at: 1.hour.ago,
                                      preview: { "success" => true, "changes" => [] }, plan: { "steps" => [] })

    expect(described_class.new(user: sam).done).to eq([page])
    expect(described_class.new(user: sam).done).not_to include(other)
  end
end
