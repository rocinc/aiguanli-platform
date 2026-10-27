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

# The assistant hears people wherever they write: forum, wiki, news, time
# entries, not only work package comments (04 D2, D3, D4, C1).
RSpec.describe "Assistant listening beyond work packages" do # rubocop:disable RSpec/DescribeClass
  shared_let(:project) do
    create(:project, enabled_module_names: %w[work_package_tracking assistant forums wiki news costs])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant view_messages add_messages
                                          view_wiki_pages edit_wiki_pages view_news comment_news])
  end
  shared_let(:ada) { create(:user, firstname: "Ada", lastname: "Lovelace", member_with_roles: { project => role }) }
  shared_let(:forum) { create(:forum, project:) }
  shared_let(:wiki) { project.wiki || create(:wiki, project:) }

  let(:llm) { instance_double(Assistant::Llm) }

  before do
    Assistant::Membership.ensure_member!(project)
    allow(Assistant::Reasoning::Agent).to receive(:new).and_return(
      instance_double(Assistant::Reasoning::Agent,
                      run: Assistant::Reasoning::Agent::Result.new(content: "Export ships in 1.4.", cards: [], rounds: 1,
                                                                 tool_calls: []))
    )
  end

  def mention = Assistant::Reasoning::StepBuilder.mention(Assistant.user)

  describe Assistant::Understanding::Sources do
    it "reads a forum reply with the topic and earlier replies as its thread" do
      topic = create(:message, forum:, author: ada, subject: "Export to PDF?", content: "Can we export?")
      reply = create(:message, forum:, parent: topic, author: ada, subject: "RE", content: "I will build it by Friday.")
      journal = reply.journals.last

      expect(described_class.subject_of(journal)).to eq(topic)
      expect(described_class.project_of(journal)).to eq(project)
      expect(described_class.text_of(journal)).to eq("I will build it by Friday.")
      expect(described_class.thread_of(journal).map(&:text)).to eq(["Export to PDF?: Can we export?"])
    end

    it "reads a wiki edit by its edit note, and a new page by its content" do
      page = create(:wiki_page, wiki:, title: "Export", text: "We export PDF only.", author: ada)

      expect(described_class.text_of(page.journals.first)).to include("Export", "We export PDF only.")

      page.update!(text: "PDF and CSV.", journal_notes: "Added CSV as decided on Monday", journal_user: ada)
      expect(described_class.text_of(page.journals.reload.last)).to eq("Added CSV as decided on Monday")
    end
  end

  describe Assistant::Called::Mention do
    it "answers a forum post in the topic, in its own name" do
      topic = create(:message, forum:, author: ada, subject: "When is export?", content: "#{mention} when does export ship?")

      action = described_class.new(topic.journals.last).call
      expect(action).to have_attributes(status: "executed"), -> { action.attributes.slice("status", "tier", "result").inspect }

      reply = topic.reload.children.last
      expect(reply.author).to eq(Assistant.user)
      expect(reply.content).to include("Export ships in 1.4.")
      expect(Assistant::Conversation.find_by(context: topic.journals.last)).to have_attributes(origin: "mention", user: ada)
    end

    it "answers under a news item" do
      news = create(:news, project:, author: ada)
      comment = news.comments.create!(author: ada, comments: "#{mention} is CSV in too?")

      described_class.new(comment).call

      expect(news.comments.reload.map(&:author)).to include(Assistant.user)
    end

    it "keeps a wiki answer in a conversation and tells the person where it is" do
      page = create(:wiki_page, wiki:, title: "Export", text: "PDF only.", author: ada)
      page.update!(text: "PDF only!", journal_notes: "#{mention} is this still right?", journal_user: ada)

      described_class.new(page.journals.reload.last).call

      signal = Assistant::Signal.find_by(detector: "mention_answer", recipient: ada)
      option = signal.options.sole
      expect(option).to include("label" => "Open the conversation")
      expect(Assistant::Conversation.find(option["conversation_id"])).to have_attributes(user: ada, origin: "mention")
      expect(page.reload.text).to eq("PDF only!")
    end
  end

  describe "the line left when it is called" do
    let(:topic) { create(:message, forum:, author: ada, subject: "When is export?", content: "#{mention} when does export ship?") }

    def line_left
      topic.reload.children.find_by(author: Assistant.user) || Assistant::Called::Placeholder.post(topic.journals.last)
    end

    it "becomes the answer instead of a second reply" do
      placeholder = line_left
      expect(placeholder.content).to eq(Assistant::Called::Placeholder.text)

      expect { Assistant::Called::Mention.new(topic.journals.last, placeholder:).call }
        .not_to change { topic.reload.children.count }

      expect(placeholder.reload.content).to include("Export ships in 1.4.")
    end

    it "becomes the apology when the model cannot answer" do
      placeholder = line_left

      Assistant::Called::Mention.new(topic.journals.last, placeholder:).apologise(:over_budget)

      expect(topic.reload.children.where(author: Assistant.user).count).to eq(1)
      expect(placeholder.reload.content).to include("budget")
    end

    it "sends what points at one person only to the one who asked" do
      allow(Assistant::Reasoning::Agent).to receive(:new).and_return(
        instance_double(Assistant::Reasoning::Agent,
                        run: Assistant::Reasoning::Agent::Result.new(content: "Export ships in 1.4.\n[私下] Ben has not logged his estimate.",
                                                                   cards: [], rounds: 1, tool_calls: []))
      )
      placeholder = line_left

      Assistant::Called::Mention.new(topic.journals.last, placeholder:).call

      expect(placeholder.reload.content).to include("Export ships in 1.4.", "privately")
      expect(placeholder.content).not_to include("Ben")
      expect(Assistant::Signal.find_by(detector: "mention_answer", recipient: ada).headline).to include("Ben has not logged")
    end
  end

  describe "when the model cannot answer" do
    it "says so where the question was asked instead of staying silent" do
      topic = create(:message, forum:, author: ada, subject: "When is export?", content: "#{mention} when does export ship?")

      Assistant::Called::Mention.new(topic.journals.last).apologise(:over_budget)

      expect(topic.reload.children.last).to have_attributes(author: Assistant.user, content: a_string_including("额度").or(a_string_including("budget")))
    end

    it "keeps no half-made conversation when the model fails, so a retry can answer" do
      failing = instance_double(Assistant::Reasoning::Agent)
      allow(failing).to receive(:run).and_raise(Assistant::Llm::RetryableError)
      allow(Assistant::Reasoning::Agent).to receive(:new).and_return(failing)
      topic = create(:message, forum:, author: ada, subject: "When is export?", content: "#{mention} when does export ship?")

      expect { Assistant::Called::Mention.new(topic.journals.last).call }.to raise_error(Assistant::Llm::RetryableError)
      expect(Assistant::Conversation.where(context: topic.journals.last)).to be_empty
    end

    it "treats an empty answer as a failure to retry" do
      allow(Assistant::Reasoning::Agent).to receive(:new).and_return(
        instance_double(Assistant::Reasoning::Agent,
                        run: Assistant::Reasoning::Agent::Result.new(content: "", cards: [], rounds: 1, tool_calls: []))
      )
      topic = create(:message, forum:, author: ada, subject: "When is export?", content: "#{mention} when does export ship?")

      expect { Assistant::Called::Mention.new(topic.journals.last).call }.to raise_error(Assistant::Llm::RetryableError)
    end
  end

  describe Assistant::Events::Dispatch do
    it "is called from a new forum post, a wiki edit note and a news comment" do
      post = create(:message, forum:, author: ada, content: "hi #{mention}")

      expect(post.journals.count).to eq(1)
      expect(described_class.journal_words(post.journals.last)).to include(mention)
      expect(described_class.mentions_assistant?("ping @#{AssistantUser::LOGIN} please")).to be(true)
    end
  end

  it "is offered as a watcher where it may see the work package, like any member (01 §2.1)" do
    work_package = create(:work_package, project:)

    expect(work_package.addable_watcher_users).to include(Assistant.user)
  end
end
