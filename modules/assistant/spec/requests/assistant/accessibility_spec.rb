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

# U6: what the assistant's pages say to people who do not see them, and that
# every sentence exists in both languages.
RSpec.describe "The assistant's pages, read without looking", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages use_assistant manage_assistant view_member_performance])
  end
  shared_let(:lea) { create(:user, member_with_roles: { project => role }) }

  def locale_keys(file)
    flatten = ->(hash, prefix) do
      hash.flat_map do |key, value|
        path = [prefix, key].compact.join(".")
        value.is_a?(Hash) ? flatten.(value, path) : [path.sub(/\.(zero|one|two|few|many|other)\z/, "")]
      end
    end
    flatten.(YAML.load_file(file).values.first, nil).uniq
  end

  %w[_ux .].each do |suffix|
    it "has every #{suffix == '.' ? 'main' : 'ux'} sentence in English and Chinese" do
      root = Rails.root.join("modules/assistant/config/locales")
      name = suffix == "." ? "" : suffix
      en = locale_keys(root.join("en#{name}.yml"))
      zh = locale_keys(root.join("crowdin/zh-CN#{name}.yml"))

      expect(en - zh).to be_empty
      expect(zh - en).to be_empty
    end
  end

  it "names every kind of duty and every option a detector can offer on the grants page" do
    expect(Assistant::Duty::KINDS).to all(satisfy { I18n.exists?("assistant.duties_page.kinds.#{it}.does", :en) })
    expect(Assistant::Duty::KINDS).to all(satisfy { I18n.exists?("assistant.duties_page.kinds.#{it}.does", :"zh-CN") })
  end

  context "when logged in" do
    before { login_as(lea) }

    it "says a duty's day and hour the way people say them" do
      Assistant::Duty.create!(project:, kind: "weekly_status", delegator: lea, scope: { "wday" => 5, "hour" => 16 })

      get project_assistant_desk_path(project, tab: "duties")

      expect(response.body).to include("Every Fri, 4 pm")
    end

    it "still shows the duties page for a kind whose words are not written yet" do
      stub_const("Assistant::Duty::KINDS", [*Assistant::Duty::KINDS, "not_yet_written"])

      get project_assistant_desk_path(project, tab: "duties")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Not yet written")
    end
  end

  describe "the admin settings page" do
    before do
      login_as(create(:admin))
      allow(Assistant::Llm).to receive(:configured?).and_return(true)
    end

    it "says what waits for reading attachments, and stops saying it once that is on" do
      get admin_settings_assistant_path
      expect(Capybara.string(response.body)).to have_test_selector("assistant-admin-attachments-off",
                                                                   text: "Document summaries")
      expect(response.body).to include("sent to the configured language model")

      Setting.assistant_read_attachments = true
      get admin_settings_assistant_path
      expect(Capybara.string(response.body)).not_to have_test_selector("assistant-admin-attachments-off")
    end
  end
end
