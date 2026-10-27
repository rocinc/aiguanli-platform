# frozen_string_literal: true

require "spec_helper"

RSpec.describe Assistant::BriefMail do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages use_assistant]) }
  shared_let(:ben) { create(:user, language: "zh-CN", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: ben) }

  # A Wednesday; the default brief time is 08:00 UTC.
  let(:morning) { Time.utc(2026, 9, 30, 8, 5) }
  let(:preference) { Assistant::Preference.for(ben) }

  before do
    Assistant::Signal.create!(detector: "stalled", fingerprint: "m", recipient: ben, project:, subject: work_package,
                              channel: "brief", score: 50, deliver_at: morning - 1.hour,
                              payload: { "headline" => "#12 已经 5 个工作日没有动静。", "because" => ["最后一次改动在 9/22"] })
    preference.update!(brief_email: true)
    ActionMailer::Base.deliveries.clear
  end

  def send_brief(now = morning) = described_class.new(now:).call

  it "sends the brief once on a working day, after the person's brief time" do
    send_brief
    send_brief(morning + 15.minutes)

    mail = ActionMailer::Base.deliveries.sole
    expect(mail.to).to eq([ben.mail])
    expect(mail.subject).to eq("今天 · 9/30（周三）")
    expect(mail.text_part.body.to_s).to include("#12 已经 5 个工作日没有动静。", "最后一次改动在 9/22")
    expect(preference.reload.brief_mailed_on).to eq(Date.new(2026, 9, 30))
  end

  it "waits for the brief time, and does not send it late in the day" do
    send_brief(morning - 1.hour)
    send_brief(morning + 6.hours)

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "does not send on a day off" do
    send_brief(Time.utc(2026, 10, 3, 8, 5))

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "sends nothing to someone who did not ask for it, and nothing when there is nothing to say" do
    preference.update!(brief_email: false)
    send_brief
    expect(ActionMailer::Base.deliveries).to be_empty

    preference.update!(brief_email: true)
    Assistant::Signal.delete_all
    send_brief
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
