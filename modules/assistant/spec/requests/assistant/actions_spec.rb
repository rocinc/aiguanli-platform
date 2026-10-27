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

RSpec.describe "Deciding on what the assistant prepared", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:outsider) { create(:user) }

  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let!(:work_package) do
    create(:work_package, project:, assigned_to: sam, start_date: Date.new(2026, 10, 12), due_date: Date.new(2026, 10, 13))
  end

  before do
    Assistant::Membership.ensure_member!(project)
    login_as(sam)
  end

  def propose(auto_execute: false, **)
    Assistant::Actions::Propose.call(
      kind: "reschedule", title: "Move it to Friday", on_behalf_of: sam, project:, subject: work_package,
      steps: [{ op: "update_work_package", type: "WorkPackage", id: work_package.id, attributes: { due_date: "2026-10-16" } }],
      basis: [{ "kind" => "quote", "label" => "planning", "quote" => "Friday is fine" }], auto_execute:, **
    )
  end

  it "shows the card and its history on the provenance page" do
    action = propose

    get assistant_action_path(action)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Move it to Friday")
    expect(response.body).to include("assistant-action-timeline")
  end

  it "hides the page from someone who cannot see the project" do
    action = propose
    login_as(outsider)

    get assistant_action_path(action)

    expect(response).to have_http_status(:not_found)
  end

  it "goes ahead, redraws every copy of the card and settles the signal that offered it" do
    action = propose
    signal = Assistant::Signal.create!(detector: "test", fingerprint: "x", recipient: sam, project:, channel: "inline",
                                       deliver_at: Time.current, action:, payload: { "headline" => "Move?" })

    post approve_assistant_action_path(action), params: { variant: "compact" }, headers: turbo

    expect(response.body).to include(%(action="replace"))
    expect(response.body).to include("[data-assistant-action-id=&#39;#{action.id}&#39;][data-assistant-variant=&#39;compact&#39;]")
    expect(action.reload.status).to eq("executed")
    expect(work_package.reload.due_date).to eq(Date.new(2026, 10, 16))
    expect(signal.reload.outcome).to eq("adopted")
  end

  describe "taking back what was done a while ago" do
    let(:action) { propose.tap { Assistant::Actions::Execute.call(it, decided_by: sam) } }

    def streamed = Capybara.string(response.body.scan(%r{<template>(.*?)</template>}m).flatten.join)

    it "undoes at once within a week" do
      action.update_columns(executed_at: 3.days.ago)

      post undo_assistant_action_path(action), headers: turbo

      expect(action.reload.status).to eq("undone")
      expect(work_package.reload.due_date).to eq(Date.new(2026, 10, 13))
    end

    it "shows what it would do first after a week, and only undoes when that is confirmed" do
      action.update_columns(executed_at: 8.days.ago)

      post undo_assistant_action_path(action), headers: turbo

      expect(response).to have_http_status(:ok)
      page = streamed
      expect(page).to have_css("[data-test-selector='assistant-action-undo-preview']", text: "Taking it back will")
      expect(page).to have_css("[data-test-selector='assistant-action-undo-change']", text: "Finish date 10/16 (Fri) → 10/13 (Tue)")
      expect(page).to have_css("[data-test-selector='assistant-action-undo-confirm']")
      expect(action.reload.status).to eq("executed")
      expect(work_package.reload.due_date).to eq(Date.new(2026, 10, 16))

      post undo_assistant_action_path(action), params: { confirm: "1" }, headers: turbo

      expect(action.reload.status).to eq("undone")
      expect(work_package.reload.due_date).to eq(Date.new(2026, 10, 13))
    end

    it "names what someone changed since and keeps it, with a single confirmation" do
      action.update_columns(executed_at: 8.days.ago)
      WorkPackage.where(id: work_package.id).update_all(due_date: Date.new(2026, 10, 20))

      post undo_assistant_action_path(action), headers: turbo

      page = streamed
      expect(page).to have_css("[data-test-selector='assistant-action-undo-kept']", text: "Finish date")
      expect(page).to have_field("keep", type: :hidden, with: "1")
      expect(work_package.reload.due_date).to eq(Date.new(2026, 10, 20))

      post undo_assistant_action_path(action), params: { confirm: "1", keep: "1" }, headers: turbo

      expect(action.reload.status).to eq("undone")
      expect(work_package.reload.due_date).to eq(Date.new(2026, 10, 20))
    end
  end

  it "declines and declines its alternatives too" do
    action = propose
    other = propose

    post reject_assistant_action_path(action), params: { siblings: [other.id] }, headers: turbo

    expect(action.reload.status).to eq("rejected")
    expect(other.reload.status).to eq("rejected")
  end

  it "lists conflicts before undoing over someone else's later change" do
    action = propose
    Assistant::Actions::Execute.call(action, decided_by: sam)
    WorkPackages::UpdateService.new(user: sam, model: work_package.reload).call(due_date: Date.new(2026, 10, 20))

    post undo_assistant_action_path(action.reload), headers: turbo

    expect(response.body).to include("assistant-action-conflicts")
    expect(action.reload.status).to eq("executed")

    post undo_assistant_action_path(action), params: { keep: "1" }, headers: turbo

    expect(action.reload.status).to eq("undone")
    expect(work_package.reload.due_date).to eq(Date.new(2026, 10, 20))
  end

  it "snoozes a signal until the next working morning and mutes a kind of signal" do
    signal = Assistant::Signal.create!(detector: "stale", fingerprint: "y", recipient: sam, project:, channel: "inline",
                                       deliver_at: Time.current, payload: { "headline" => "Stale" })

    patch assistant_signal_path(signal), params: { outcome: "snoozed" }, headers: turbo

    expect(signal.reload).to have_attributes(state: "held", outcome: nil)
    expect(signal.snoozed_until).to be > Time.current

    patch assistant_signal_path(signal), params: { outcome: "muted" }, headers: turbo

    expect(signal.reload.outcome).to eq("muted")
    expect(Assistant::Preference.effective(sam).muted?("stale")).to be(true)
  end
end
