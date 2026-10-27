# frozen_string_literal: true

require "spec_helper"

RSpec.describe "The assistant's page in the project settings", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:manager_role) { create(:project_role, permissions: %i[view_work_packages use_assistant manage_assistant]) }
  shared_let(:member_role) { create(:project_role, name: "开发", permissions: %i[view_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, language: "zh-CN", member_with_roles: { project => manager_role }) }
  shared_let(:ben) { create(:user, language: "zh-CN", member_with_roles: { project => member_role }) }

  let(:preference) { Assistant::Preference.find_by!(owner: project) }
  let(:rules) { Assistant::Proactive::Catalog.keys }

  before { login_as(sam) }

  def save!(**params)
    patch project_settings_assistant_path(project),
          params: { level: "", role_levels: {}, rules: ["", *rules], lead_ids: [""], duties: ["", *Assistant::Duty::KINDS],
                    token_cap: "" }.merge(params)
  end

  it "is a tab of the project settings for the project's managers" do
    get project_settings_assistant_path(project)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("项目默认档位", "按角色的默认档位", "项目里开着的提示", "项目负责人", "可以交给我的职责", "每月用量上限")
    expect(response.body).to include("开发")
    expect(Assistant::ProjectPage.new(project).roles.map(&:name)).to contain_exactly("开发", manager_role.name)
    expect(response.parsed_body.css("a[href$='/settings/assistant']").map { it.text.strip }).to include("AI 助理")
  end

  it "keeps it away from members who may not manage" do
    login_as(ben)

    get project_settings_assistant_path(project)
    expect(response).to have_http_status(:forbidden)

    save!(level: "active")
    expect(response).to have_http_status(:forbidden)
    expect(Assistant::Preference.find_by(owner: project)).to be_nil
  end

  it "saves the level, the level by role, the rules, the leads, the duties and the cap" do
    save!(level: "quiet", role_levels: { member_role.id.to_s => "active", "0" => "quiet" }, rules: ["", *(rules - %w[stalled])],
          lead_ids: ["", sam.id.to_s, create(:user).id.to_s], duties: %w[decision_log], token_cap: "5000")
    follow_redirect!

    expect(response.parsed_body.css("[data-test-selector='assistant-settings-note']").map { it.text.strip }).to eq(["已保存。"])
    expect(preference.proactivity).to eq("quiet")
    expect(preference.role_levels).to eq(member_role.id.to_s => "active")
    expect(preference.muted_detectors).to eq(["stalled"])
    settings = Assistant::Proactive::ProjectSettings.for(project)
    expect(settings.lead_ids).to eq([sam.id])
    expect(settings.duty_allowed?("decision_log")).to be(true)
    expect(settings.duty_allowed?("weekly_status")).to be(false)
    expect(settings.token_cap).to eq(5000)
  end

  it "gives a member the level of the role, unless the member chose one" do
    save!(level: "quiet", role_levels: { member_role.id.to_s => "active" })

    expect(Assistant::Preference.effective(ben, project).level).to eq("active")
    expect(Assistant::Preference.effective(sam, project).level).to eq("quiet")

    Assistant::Preference.for(ben).update!(proactivity: "standard")
    expect(Assistant::Preference.effective(ben, project).level).to eq("standard")
  end

  it "pauses a duty that is no longer allowed and no longer offers it" do
    duty = Assistant::Duty.create!(project:, kind: "weekly_status", delegator: sam)

    save!(duties: %w[decision_log])

    expect(duty.reload).not_to be_active
    expect(Assistant::DutiesPageComponent.new(project:, user: sam).open_kinds).to eq(%w[decision_log])
    post project_assistant_duties_path(project), params: { kind: "sprint_carryover" }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "stops the model calls of a project that used up its own limit, and only that project" do
    other = create(:project, enabled_module_names: %w[assistant])
    save!(token_cap: "1000")
    Assistant::Usage.create!(project:, user: sam, purpose: "x", prompt_tokens: 900, completion_tokens: 200)

    expect(Assistant::Usage.over_budget?(project:)).to be(true)
    expect(Assistant::Usage.over_budget?(project: other)).to be(false)
    expect(Assistant::Usage.near_budget?(project:)).to be(true)
  end
end
