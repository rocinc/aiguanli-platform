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

require "rails_helper"

RSpec.describe Assistant::NoticeComponent, type: :component do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search API", assigned_to: sam) }

  def make_action(title, tier)
    Assistant::Action.create!(kind: "reschedule", title:, tier:, status: "proposed", project:, on_behalf_of: sam,
                              preview: { "success" => true, "changes" => [] }, plan: { "steps" => [] })
  end

  let(:t1) { make_action("Let Quinn take #75", "t1") }
  let(:t2) { make_action("Push v2.0 to 10/9", "t2") }
  let(:payload) do
    { "headline" => "#69 is on the v2.0 critical path and has slipped twice.",
      "because" => ["#69 → #73 → #75 → v2.0 (10/2)", "Moved on 9/12 and 9/17"], "certainty" => "fact",
      "options" => [{ "label" => "Parallel", "consequence" => "version holds", "action_id" => t1.id },
                    { "label" => "Push (v2.0 slips)", "action_id" => t2.id }] }
  end
  let(:signal) do
    Assistant::Signal.create!(detector: "critical_slip", fingerprint: "f", recipient: sam, project:, subject: work_package,
                              channel: "brief", deliver_at: Time.current, payload:)
  end

  def render_notice(density = :card, **) = render_inline(described_class.new(signal:, user: sam, density:, **))

  it "has the six parts of a notice on a card" do
    render_notice

    expect(page).to have_test_selector("assistant-notice-headline", text: "critical path")
    expect(page).to have_test_selector("assistant-notice-basis", text: "Moved on 9/12 and 9/17")
    expect(page).to have_test_selector("assistant-notice-option", text: "Parallel · version holds")
    expect(page).to have_test_selector("assistant-notice-why")
    expect(page).to have_test_selector("assistant-notice-controls")
  end

  it "lets the person say something about it, on a card and on a line" do
    %i[card line].each do |density|
      render_notice(density)

      expect(page).to have_css("[data-test-selector='assistant-say'][data-assistant-context='#{signal.to_gid}']", text: "Say something",
                                                                                                                visible: :all)
    end
  end

  it "does not offer to talk about someone else's notice" do
    other = create(:user, member_with_roles: { project => role })
    render_inline(described_class.new(signal:, user: other))

    expect(page).to have_no_css("[data-test-selector='assistant-say']", visible: :all)
  end

  it "types every basis line and makes it a link" do
    render_notice

    expect(page).to have_css(".assistant-notice--basis-kind", text: I18n.t("assistant.notice.basis_kinds.chain"), count: 2,
                                                              visible: :all)
    expect(page).to have_css(".assistant-notice--basis-item a[href]", count: 2, visible: :all)
  end

  it "types the basis of a duty's notice instead of calling it a calculation" do
    signal.update!(detector: "duty_timesheet_draft")

    render_notice

    expect(page).to have_css(".assistant-notice--basis-kind", text: I18n.t("assistant.notice.basis_kinds.history"), count: 2,
                                                              visible: :all)
    expect(page).to have_no_css(".assistant-notice--basis-kind", text: I18n.t("assistant.notice.basis_kinds.calculation"),
                                                                 visible: :all)
  end

  it "shows a T1 option as a button that goes ahead and a T2 option as one that previews first" do
    render_notice

    expect(page).to have_css("form[action='#{Rails.application.routes.url_helpers.approve_assistant_action_path(t1)}'] button",
                             text: "Parallel")
    expect(page).to have_css("details.assistant-notice--confirm summary", text: "Push · v2.0 slips…")
  end

  it "turns an option that carries a reply draft into a button that fills the reply box" do
    payload["options"] = [{ "label" => "Say yes for 11/6", "reply_draft" => "I can do it by 11/6." }]

    render_notice(:line)

    expect(page).to have_css("a[data-controller='work-packages--activities-tab--reply-draft']" \
                             "[data-work-packages--activities-tab--reply-draft-text-param='I can do it by 11/6.']",
                             text: "Say yes for 11/6", visible: :all)
  end

  it "keeps the second draft, the one asking someone else, hidden until the option that fills the reply box is clicked" do
    ask = Assistant::Action.create!(kind: "request_alternate", title: "Ask Quinn", tier: "t2", status: "proposed", project:,
                                    on_behalf_of: sam, preview: { "success" => true, "changes" => [] },
                                    plan: { "steps" => [{ "op" => "comment", "as" => "person", "type" => "WorkPackage",
                                                          "id" => work_package.id,
                                                          "attributes" => { "notes" => "Quinn could you take this?" } }] })
    payload["options"] = [{ "label" => "Ask Quinn", "reply_draft" => "I cannot fit this in.", "action_id" => ask.id }]

    render_notice(:line)

    id = "assistant-notice-#{signal.id}-line-ask-#{ask.id}"
    expect(page).to have_css("a[data-controller~='assistant--reveal'][data-assistant--reveal-id-param='#{id}']", visible: :all)
    expect(page).to have_css("##{id}[hidden] [data-test-selector='assistant-draft-form']", visible: :all)
    expect(page).to have_css("##{id} [data-test-selector='assistant-draft-signature']", text: I18n.t("assistant.draft.signature.person"),
                                                                                        visible: :all)
  end

  it "shows the assistant's introduction as plain text with only an acknowledgement" do
    payload.merge!("nature" => "intro", "options" => [], "because" => ["I will keep track", "I will not name anyone", "First two weeks"])

    render_notice(:line)

    expect(page).to have_test_selector("assistant-notice-intro", text: "I will not name anyone", visible: :all)
    expect(page).to have_button(I18n.t("assistant.notice.got_it"), visible: :all)
    expect(page).to have_no_test_selector("assistant-notice-basis", visible: :all)
    expect(page).to have_no_test_selector("assistant-notice-why", visible: :all)
    expect(page).to have_no_test_selector("assistant-notice-controls", visible: :all)
  end

  it "marks a guess and says it is one" do
    payload["certainty"] = "likely"

    render_notice

    expect(page).to have_test_selector("assistant-notice-guess")
    expect(page).to have_css("[title='#{I18n.t('assistant.notice.guess')}']")
  end

  it "offers the four reasons under 'this is wrong' and the project/all scopes under mute" do
    render_notice

    %w[wrong known not_mine bad_timing].each do |reason|
      expect(page).to have_css("form input[name=outcome][value=#{reason}]", visible: :all)
    end
    expect(page).to have_css("form input[name=scope][value=project]", visible: :all)
    expect(page).to have_css("form input[name=scope][value=all]", visible: :all)
  end

  it "folds everything but one option on a line" do
    render_notice(:line)
    expect(page).to have_css("details.assistant-notice--fold")
    expect(page).to have_css("summary [data-test-selector=assistant-notice-option]", count: 1, visible: :all)
    expect(page).to have_test_selector("assistant-notice-controls", visible: :all)
  end

  it "never uses warning colours" do
    render_notice

    expect(page.native.to_html).not_to match(/danger|attention/)
  end

  it "says why with one of the closed set" do
    expect(Assistant::Notice::Why.new(signal, sam).key).to eq("owns")
    expect(Assistant::Notice::Why::KEYS).to include(Assistant::Notice::Why.new(signal, sam).key)
  end

  it "replaces itself with the reply it was given" do
    render_notice(reply: "OK.")

    expect(page).to have_test_selector("assistant-notice-reply", text: "OK.")
    expect(page).to have_no_test_selector("assistant-notice-controls")
  end

  describe "when the fact no longer holds" do
    before { signal.update!(state: "expired", outcome: "resolved", outcome_at: 1.hour.ago) }

    it "leaves one grey line for a day" do
      render_notice

      expect(page).to have_test_selector("assistant-notice-stale",
                                         text: I18n.t("assistant.notice.stale_subject", ref: "##{work_package.id}"))
    end

    it "is gone after 24 hours" do
      signal.update!(outcome_at: 25.hours.ago)

      expect(render_notice.to_html).to be_blank
    end
  end
end
