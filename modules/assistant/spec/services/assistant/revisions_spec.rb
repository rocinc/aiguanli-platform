# frozen_string_literal: true

require "rails_helper"

RSpec.describe Assistant::Revisions do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_project use_assistant]) }
  shared_let(:lea) { create(:user, member_with_roles: { project => role }) }
  shared_let(:other) { create(:user, member_with_roles: { project => role }) }

  let(:duty) { Assistant::Duty.create!(project:, kind: "weekly_status", delegator: lea) }
  let(:draft) do
    Assistant::Actions::Propose.call(
      kind: "weekly_status", title: "Status", on_behalf_of: lea, project:, subject: project, auto_execute: false,
      basis: [Assistant::Basis.for(duty)],
      steps: [{ "op" => "update_project_status", "type" => "Project", "id" => project.id,
                "attributes" => { "status_code" => "at_risk",
                                  "status_explanation" => "The API is late and the review has not started yet." } }]
    )
  end

  def revise(text, action: draft) = Assistant::Actions::Revise.call(action, user: lea, edits: { "0" => { "status_explanation" => text } })

  def stored = Assistant::Preference.find_by(owner: lea)&.thresholds.to_h.dig("revisions", "weekly_status")

  it "keeps a heavy rewrite under the kind of draft and the person" do
    revise("Nothing is late, the team is ahead of plan.")

    expect(stored).to eq([{ "attribute" => "status_explanation",
                            "before" => "The API is late and the review has not started yet.",
                            "after" => "Nothing is late, the team is ahead of plan." }])
  end

  it "keeps nothing when only a few words changed" do
    revise("The API is late and the review has not started yet, sadly.")

    expect(draft.reload.plan["edits"].size).to eq(1)
    expect(stored).to be_nil
  end

  it "measures a rewrite of text written without spaces" do
    expect(described_class.change("接口延期了，评审还没有开始。", "接口延期了，评审还没有开始，请注意。")).to be < described_class::HEAVY
    expect(described_class.change("接口延期了，评审还没有开始。", "一切顺利，团队进度领先。")).to be > described_class::HEAVY
  end

  it "keeps the last five, and hands over the newest three first" do
    texts = %w[alpha bravo charlie delta echo foxtrot golf].map { |word| "#{word} #{word.reverse} #{word * 3}, #{word.upcase}" }
    texts.each { revise(it) }

    expect(stored.size).to eq(5)
    expect(described_class.examples(lea, "weekly_status").pluck("after"))
      .to eq(texts.last(3).reverse)
  end

  it "is nobody else's" do
    revise("Nothing is late, the team is ahead of plan.")

    expect(described_class.examples(other, "weekly_status")).to be_empty
  end

  it "reaches the prompt of the next draft of the duty, and only then" do
    writer = Assistant::Duties::WeeklyStatus.new(duty)
    llm = instance_double(Assistant::Llm, json: {})
    allow(writer).to receive(:llm).and_return(llm)

    writer.send(:write, "Write.", { "facts" => 1 })
    expect(llm).to have_received(:json).with(hash_including(user: '{"facts":1}', system: satisfy { !it.include?("earlier_edits") }))

    revise("Nothing is late, the team is ahead of plan.")
    writer.send(:write, "Write.", { "facts" => 1 })

    expect(llm).to have_received(:json).with(hash_including(user: include("Nothing is late, the team is ahead of plan."),
                                                            system: include("rewrote")))
  end
end
