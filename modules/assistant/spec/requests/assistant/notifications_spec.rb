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

RSpec.describe "An assistant notification in the notification center", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking wiki assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages use_assistant view_wiki_pages]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:) }
  shared_let(:version) { create(:version, project:) }

  before do
    Assistant::Membership.ensure_member!(project)
    login_as(sam)
  end

  def notified!(subject, headline)
    signal = Assistant::Signal.create!(detector: "stalled", fingerprint: SecureRandom.hex(4), recipient: sam, project:, subject:,
                                       channel: "notification", deliver_at: 1.minute.ago,
                                       payload: { "headline" => headline, "because" => ["x"], "nature" => "own" })
    allow_any_instance_of(Assistant::Proactive::Timing).to receive(:may_interrupt?).and_return(true) # rubocop:disable RSpec/AnyInstance
    Assistant::Proactive::Delivery.new.call
    Notification.find(signal.reload.payload["notification_id"])
  end

  it "carries the headline only and takes the person to the work package, where the notice is waiting" do
    notification = notified!(work_package, "#69 已 20 个工作日没动")

    expect(notification).to have_attributes(reason: "assistant", subject: "#69 已 20 个工作日没动", mail_alert_sent: nil,
                                            mail_reminder_sent: nil)

    get assistant_notification_path(notification)
    expect(response).to redirect_to(work_package_path(work_package))

    get assistant_work_package_line_path(work_package)
    expect(response.parsed_body.css(".assistant-notice--headline").map(&:text)).to eq(["#69 已 20 个工作日没动"])
  end

  it "takes the person to the version it is about, not to the project" do
    notification = notified!(version, "v2.0 有 3 项没有日期")

    get assistant_notification_path(notification)

    expect(response).to redirect_to(version_path(version))
  end

  it "is not repeated in the brief, because the page is where it lives" do
    notified!(work_package, "#69 已 20 个工作日没动")

    expect(Assistant::Brief.new(user: sam).decisions).to be_empty
  end
end
