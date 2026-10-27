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

RSpec.describe "The assistant's project pages", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:manager_role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant manage_assistant view_members
                                          view_member_performance appraise_members])
  end
  shared_let(:member_role) { create(:project_role, permissions: %i[view_work_packages use_assistant view_members]) }
  shared_let(:sam) { create(:user, firstname: "Sam", lastname: "Lead", member_with_roles: { project => manager_role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "Dev", member_with_roles: { project => member_role }) }

  describe "duties" do
    before { login_as(sam) }

    it "offers every kind when nothing is handed over, and says why the list is empty" do
      get project_assistant_desk_path(project, tab: "duties")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("assistant-duties-empty")
      expect(response.body.scan("assistant-duty-create").size).to eq(Assistant::Duty::KINDS.size)
      expect(response.body).to include("assistant-duty-hand-over")
    end

    it "hands a duty over with its scope, pauses it and takes it out, morphing the page in place" do
      post project_assistant_duties_path(project, format: :turbo_stream),
           params: { kind: "weekly_status", scope: { wday: "4", hour: "15", evil: "x" } }

      duty = Assistant::Duty.find_by!(project:, kind: "weekly_status")
      expect(duty).to have_attributes(delegator: sam, scope: { "wday" => "4", "hour" => "15" })
      expect(response.body).to include(%(method="morph"))
      expect(response.body).to include("Handed over: Weekly project status")

      patch project_assistant_duty_path(project, duty, format: :turbo_stream), params: { active: "0" }
      expect(duty.reload).not_to be_active

      delete project_assistant_duty_path(project, duty, format: :turbo_stream)
      expect(Assistant::Duty.exists?(duty.id)).to be(false)
    end

    it "lets a team stop being asked about a kind it has decided on, and take that back" do
      Assistant::Action.create!(kind: "said_change", title: "Move #1", tier: "t2", status: "executed", project:,
                                decided_by: sam, on_behalf_of: sam, plan: { "steps" => [] }, preview: {})

      get project_assistant_desk_path(project, tab: "duties")
      expect(response.body).to include("assistant-grant-candidate")

      post project_assistant_grants_path(project, format: :turbo_stream), params: { action_kind: "said_change" }
      grant = Assistant::Grant.live.find_by!(project:, action_kind: "said_change")

      delete project_assistant_grant_path(project, grant, format: :turbo_stream)
      expect(grant.reload.revoked_at).to be_present
    end

    it "refuses a grant for a kind nobody here was ever asked about" do
      post project_assistant_grants_path(project, format: :turbo_stream), params: { action_kind: "publish_news" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Assistant::Grant.count).to eq(0)
    end

    it "is read by a member without the permission, who sees no buttons and cannot change anything" do
      duty = Assistant::Duty.create!(project:, kind: "weekly_status", delegator: sam)
      login_as(ben)
      get project_assistant_desk_path(project, tab: "duties")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Weekly project status", "assistant-duties")
      expect(response.body).not_to include("assistant-duty-toggle", "assistant-duty-hand-over", "assistant-duty-edit")

      patch project_assistant_duty_path(project, duty, format: :turbo_stream), params: { active: "0" }
      expect(response).to have_http_status(:forbidden)
      post project_assistant_duties_path(project, format: :turbo_stream), params: { kind: "decision_log" }
      expect(response).to have_http_status(:forbidden)
      expect(duty.reload).to be_active
    end

    it "lets the person who handed a duty over change it even without the permission, but nobody else's" do
      mine = Assistant::Duty.create!(project:, kind: "decision_log", delegator: ben)
      others = Assistant::Duty.create!(project:, kind: "weekly_status", delegator: sam)
      login_as(ben)

      patch project_assistant_duty_path(project, mine, format: :turbo_stream),
            params: { scope: { ceiling: "draft", title: "No such page" } }
      expect(response).to have_http_status(:ok)
      expect(mine.reload.scope).to eq("ceiling" => "draft")

      patch project_assistant_duty_path(project, others, format: :turbo_stream), params: { active: "0" }
      expect(response).to have_http_status(:forbidden)
    end

    it "asks whether a duty is still needed after four runs nobody opened, and starts counting again on keep" do
      duty = Assistant::Duty.create!(project:, kind: "weekly_status", delegator: sam, unseen_runs: 4)

      get project_assistant_desk_path(project, tab: "duties")
      expect(response.body).to include("assistant-duty-stale", "assistant-duty-keep")

      patch project_assistant_duty_path(project, duty, format: :turbo_stream), params: { keep: "1" }
      expect(duty.reload.unseen_runs).to eq(0)
    end

    it "says what a duty last did and when it runs next, in words" do
      Assistant::Duty.create!(project:, kind: "weekly_status", delegator: sam, last_run_at: 1.hour.ago,
                              last_result: { "summary" => "empty", "action_ids" => [], "produced" => false })

      get project_assistant_desk_path(project, tab: "duties")

      expect(response.body).to include("Looked, nothing usable to write this time")
      expect(response.body).to include("Every Fri, 4 pm")
    end

    it "refuses a kind that is not in the catalog" do
      post project_assistant_duties_path(project, format: :turbo_stream), params: { kind: "not_a_duty" }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "member performance" do
    it "shows a member without the permission their own page in full, and sends them nowhere else" do
      login_as(ben)
      get project_member_performance_path(project, ben)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("This is exactly what anyone appraising you sees.")
      expect(response.body).to include("Nobody else has looked at this page in the last 90 days.")

      get project_performance_team_path(project)
      expect(response).to have_http_status(:forbidden)
    end

    it "says nothing about a written appraisal to the member while it is still a draft" do
      Assistant::Appraisal.create!(project:, subject: ben, author: sam, narrative: "Draft text", period_start: 90.days.ago,
                                   period_end: Date.current)
      login_as(ben)
      get project_member_performance_path(project, ben)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Draft text", "being written", "No written appraisal")
      expect(response.body).not_to include("assistant-appraisal-written")
    end

    it "refuses one member another's page" do
      login_as(ben)
      get project_member_performance_path(project, sam)

      expect(response).to have_http_status(:forbidden)
    end

    it "does not open for someone who cannot see the project" do
      login_as(create(:user))
      get project_member_performance_path(project, ben)

      expect(response).to have_http_status(:not_found)
    end

    it "records every look by someone else, and the member sees who looked" do
      login_as(sam)
      get project_performance_team_path(project)
      expect(response.body).to include("Ben Dev")

      get project_member_performance_path(project, ben)
      expect(Assistant::AppraisalView.where(viewer: sam, subject: ben).count).to eq(1)

      login_as(ben)
      get project_member_performance_path(project, ben)
      expect(response.body).to include("1 person looked at this page: Sam Lead")
      expect(response.body).to include("Sam Lead looked on")
    end

    it "lets the member add their side, and only them" do
      login_as(ben)
      post project_member_performance_notes_path(project, ben, format: :turbo_stream),
           params: { metric_key: "delivery", note: "Those two weeks I was helping another project." }
      expect(Assistant::AppraisalNote.find_by(subject: ben, metric_key: "delivery")).to be_present

      login_as(sam)
      post project_member_performance_notes_path(project, ben, format: :turbo_stream),
           params: { metric_key: "delivery", note: "x" }
      expect(response).to have_http_status(:forbidden)
    end

    it "keeps a draft with the appraiser and shows the member the final text" do
      draft = Assistant::Appraisal.create!(subject: ben, project:, author: sam, period_start: 90.days.ago.to_date,
                                           period_end: Date.current, narrative: "Draft that Ben should not see yet")
      login_as(ben)
      get project_member_performance_path(project, ben)
      expect(response.body).not_to include("Draft that Ben should not see yet")

      login_as(sam)
      post project_finalize_member_performance_path(project, ben, format: :turbo_stream),
           params: { appraisal_id: draft.id, narrative: "Delivered 8 of 10 on time." }
      expect(draft.reload).to be_finalized

      login_as(ben)
      get project_member_performance_path(project, ben)
      expect(response.body).to include("Delivered 8 of 10 on time.")
    end

    it "lists a person's own projects on their own page, with who looked" do
      Assistant::AppraisalView.create!(viewer: sam, subject: ben, project:, created_at: Time.current)
      login_as(ben)
      get my_performance_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("assistant-my-performance-project")
      expect(response.body).to include("Sam Lead")
    end

    it "offers [look at performance] on member rows only to those who may" do
      login_as(sam)
      get project_members_path(project)
      expect(response.body).to include(project_member_performance_path(project, ben))
      expect(response.body).to include(project_performance_team_path(project))

      login_as(ben)
      get project_members_path(project)
      expect(response.body).not_to include(project_member_performance_path(project, sam))
      expect(response.body).not_to include(project_performance_team_path(project))
    end
  end

  describe "an archived project" do
    shared_let(:admin) { create(:admin) }

    before do
      project.update_column(:active, false)
      login_as(admin)
    end

    after { project.update_column(:active, true) }

    it "can be looked at by an administrator but not changed" do
      get project_assistant_desk_path(project, tab: "duties")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("You can look, but not change anything.")
      expect(response.body).not_to include("assistant-duty-create")

      post project_assistant_duties_path(project, format: :turbo_stream), params: { kind: "weekly_status" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(Assistant::Duty.count).to eq(0)
    end
  end
end
