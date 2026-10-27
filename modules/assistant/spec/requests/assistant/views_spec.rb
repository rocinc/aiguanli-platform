# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

# 02 §1.1: what someone has had in view, so the gate does not tell them again.
RSpec.describe "The page beacon", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:ben) { create(:user, member_with_roles: { project => role }) }
  shared_let(:outsider) { create(:user) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: ben) }

  it "records that the person had it open, marks what was shown there as seen, and the gate counts it as known" do
    signal = Assistant::Signal.create!(detector: "stalled", fingerprint: "x", recipient: ben, project:, subject: work_package,
                                       channel: "inline", state: "delivered", score: 10, deliver_at: 1.hour.ago, payload: {})
    login_as ben

    post assistant_views_path, params: { type: "work_package", id: work_package.id }

    expect(response).to have_http_status(:no_content)
    expect(Assistant::View.seen_since?(ben, work_package, 1.minute.ago)).to be(true)
    expect(signal.reload.seen_at).to be_present

    signal.destroy
    candidate = Assistant::Proactive::Candidate.build(detector: "stalled", project:, fingerprint: "y", recipient: ben,
                                                      subject: work_package, headline: "Stalled",
                                                      facts: { since: 1.hour.ago })
    expect(Assistant::Proactive::Gate.new(candidate).call.reasons).to include("already_known")
  end

  it "records nothing about what the person may not see, and answers the same" do
    login_as outsider

    post assistant_views_path, params: { type: "work_package", id: work_package.id }

    expect(response).to have_http_status(:no_content)
    expect(Assistant::View.where(user: outsider)).to be_empty
  end

  it "puts the beacon on the page of the object, and none where there is no object" do
    login_as ben

    get project_work_package_path(project, work_package)
    follow_redirect! while response.redirect?
    beacon = Capybara.string(response.body).find("[data-controller='assistant--beacon']", visible: :all)
    expect(beacon["data-assistant--beacon-type-value"]).to eq("work_package")
    expect(beacon["data-assistant--beacon-id-value"]).to eq(work_package.id.to_s)

    get my_page_path
    expect(response.body).not_to include("assistant--beacon")
  end
end
