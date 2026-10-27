# frozen_string_literal: true

require "spec_helper"

RSpec.describe "The assistant settings of one person", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, name: "智能写作平台", enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:manager_role) { create(:project_role, permissions: %i[view_work_packages use_assistant manage_assistant]) }
  shared_let(:ada) { create(:user, language: "zh-CN", member_with_roles: { project => manager_role }) }
  shared_let(:outsider) { create(:user, language: "zh-CN") }

  def preference = Assistant::Preference.find_by!(owner: ada)
  let(:notes) { response.parsed_body.css("[data-test-selector='assistant-settings-note']").map { it.text.strip } }

  before { login_as(ada) }

  it "has the five items in order, in the person's words" do
    get my_assistant_path

    expect(response).to have_http_status(:ok)
    headings = response.parsed_body.css("main h2, #content h2").map { it.text.strip }
    expect(headings).to include("我多主动", "每天最多打断", "简报", "不用告诉我的事", "它替我做事")
    expect(response.body).to include("在这个项目里不一样", "智能写作平台", "每天 08:00")
    expect(response.parsed_body.at_css("#content").text).not_to match(/proactive|detector|interrupt_cap|brief_email/i)
  end

  it "saves the level, the cap, the brief mail and the level of one project, and says so next to the button" do
    patch my_assistant_path, params: { proactivity: "quiet", interrupt_cap: "1", brief_email: "1",
                                       project_levels: { project.id.to_s => "active", "0" => "quiet" } }
    follow_redirect!

    expect(preference).to have_attributes(proactivity: "quiet", interrupt_cap: 1, cap_chosen?: true, brief_email: true)
    expect(preference.project_levels).to eq(project.id.to_s => "active")
    expect(Assistant::Preference.effective(ada, project).level).to eq("active")
    expect(notes).to eq(["已保存。"])
  end

  it "follows the project again when the choice is emptied" do
    Assistant::Preference.for(ada).update!(proactivity: "quiet", interrupt_cap: 1,
                                           project_levels: { project.id.to_s => "active" })

    patch my_assistant_path,
          params: { proactivity: "", interrupt_cap: "", brief_email: "0", project_levels: { project.id.to_s => "" } }

    expect(preference).to have_attributes(proactivity: nil, interrupt_cap: nil, cap_chosen?: false, brief_email: false,
                                          project_levels: {})
  end

  it "lists the muted rules by name, global and per project, and turns them back on" do
    Assistant::Preference.for(ada).tap { it.mute!("stalled") }.mute_in!("critical_slip", project)

    get my_assistant_path
    expect(response.body).to include("停滞的工作", "关键路径延误", "（在“智能写作平台”里）")

    delete mute_my_assistant_path(rule: "stalled")
    expect(preference.muted_detectors).to eq([])
    expect(preference.muted_in_projects).not_to be_empty

    delete mute_my_assistant_path(rule: "critical_slip", project_id: project.id)
    expect(preference.muted_in_projects).to eq({})
    follow_redirect!
    expect(response.body).to include("你没有关掉任何一类提示。")
  end

  it "lists what the person let it do, and takes it back" do
    grant = Assistant::Grant.create!(project:, action_kind: "reschedule", granted_by: ada)
    Assistant::Grant.create!(project:, action_kind: "close", granted_by: create(:user))

    get my_assistant_path
    expect(response.body).to include("调整日期")
    expect(response.body).not_to include("关闭已说完成的工作")

    delete grant_my_assistant_path(grant)
    expect(grant.reload.revoked_at).to be_present
    follow_redirect!
    expect(response.body).to include("你还没有让我直接做过任何事")
  end

  it "cannot take back what someone else allowed" do
    other = Assistant::Grant.create!(project:, action_kind: "close", granted_by: create(:user))

    delete grant_my_assistant_path(other)

    expect(response).to have_http_status(:not_found)
    expect(other.reload.revoked_at).to be_nil
  end

  it "is closed to someone who has the assistant nowhere" do
    login_as(outsider)

    get my_assistant_path

    expect(response).to have_http_status(:forbidden)
  end
end
