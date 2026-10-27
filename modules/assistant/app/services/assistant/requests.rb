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

module Assistant
  # Someone asks for something in a forum topic (06 S3). The assistant says
  # in the topic only what is so: there is #x planned for v2.1, or there is
  # nothing yet and a draft waits for the product lead. The draft goes into
  # that lead's brief with type, acceptance criteria, an estimate from
  # similar work and a version; once it is created, or when it is done and
  # shipped, the topic is told.
  class Requests
    MATCH = 0.45
    SYSTEM = <<~PROMPT
      You read one forum post from a software project's users. Decide whether it asks for a change
      to the product: a missing feature, a bug, an improvement. Questions, thanks and discussion are not.
      Answer as JSON: {"request": true|false, "kind": "feature"|"bug", "subject": "...",
      "description": "...", "acceptance": ["...", "..."]}
      - subject: at most 80 characters, says what should be true afterwards, in the post's language.
      - description: two or three sentences: who needs it, what is wrong now, quoting the post.
      - acceptance: two to four checkable criteria.
      Use only what the post says; leave out anything you would have to guess.
    PROMPT

    def self.for(message, llm: nil) = new(message, llm:)

    def initialize(message, llm: nil)
      @message = message
      @topic = message.root
      @project = @topic.project
      @llm = llm
    end

    attr_reader :message, :topic, :project

    def call
      return unless applies?

      reading = read
      return unless reading["request"] == true && reading["subject"].present?

      OpenProject::LocaleHelper.with_locale_for(message.author) do
        existing = matching(reading["subject"])
        existing ? point_to(existing) : draft(reading)
      end
    end

    # Told when a work package that came from a forum post is created,
    # finished, or ships in a version.
    def self.follow_up!(work_package)
      FollowUp.open.where(work_package:).find_each do |follow_up|
        new(follow_up.place.root).tell(follow_up)
      end
    end

    def tell(follow_up)
      wp = follow_up.work_package
      what, text = news_for(follow_up, wp)
      return unless what
      return if follow_up.asker && Assistant::Signal.silenced?("forum_followup", recipient: follow_up.asker, project:)

      reply!(text, kind: "follow_up_reply", title: I18n.t("assistant.requests.follow_up_title", ref: "##{wp.id}"))
      follow_up.told!(what)
      follow_up.update!(state: what == "released" ? "released" : (what == "done" ? "done" : follow_up.state))
    end

    private

    def applies?
      return false if message.author.nil? || message.author.is_a?(AssistantUser) || message != topic
      return false unless project&.module_enabled?(:assistant) && Assistant::Llm.configured?

      !FollowUp.exists?(place: topic) && !answered_by_assistant?
    end

    def answered_by_assistant? = topic.children.exists?(author_id: Assistant.user.id)

    def read
      text = [topic.subject, Assistant::Text.plain(topic.content)].join("\n")
      llm.json(system: SYSTEM, user: text.truncate(4000), max_tokens: 600)
    rescue Assistant::Llm::Error => e
      Rails.logger.warn("[assistant] request reading for message #{topic.id}: #{e.message}")
      {}
    end

    def llm = @llm ||= Assistant::Llm.new(purpose: "forum_request", user: message.author, project:)

    # Open work that already says the same thing, by words in its subject.
    def matching(subject)
      candidates = WorkPackage.where(project:).where.not(status_id: Assistant::Facts.closed_status_ids)
                              .order(updated_at: :desc).limit(400)
      best = candidates.map { [Assistant::Text.overlap(it.subject, subject).first, it] }.max_by(&:first)
      best&.first.to_f >= MATCH ? best.last : nil
    end

    def point_to(wp)
      version = Assistant::Facts.version_of(wp)
      text = if version
               I18n.t("assistant.requests.planned", ref: "##{wp.id}", version: version.name)
             else
               I18n.t("assistant.requests.known", ref: "##{wp.id}")
             end
      remember(wp)
      reply!(text, kind: "request_reply", title: I18n.t("assistant.requests.reply_title", subject: topic.subject.truncate(40)))
    end

    # The work package is drafted as a proposal for the product lead, who
    # creates it with one click; until then the topic hears that it waits.
    def draft(reading)
      lead = Assistant::Proactive::Routing.leads(project).first or return
      estimate = Assistant::Facts::Estimate.new(project, text: reading["subject"])
      version = suggested_version
      type = type_for(reading["kind"])
      attributes = { "project_id" => project.id, "type_id" => type&.id, "subject" => reading["subject"].truncate(255),
                     "description" => description(reading), "estimated_hours" => estimate.hours,
                     "version_id" => version&.id }.compact
      action = Assistant::Actions::Propose.call(
        kind: "request_draft", title: I18n.t("assistant.requests.draft_title", subject: attributes["subject"]),
        steps: [{ "op" => "create_work_package", "attributes" => attributes }], on_behalf_of: lead, project:,
        subject: topic, basis: [Assistant::Basis.for(topic, quote: Assistant::Text.plain(topic.content).truncate(200))],
        auto_execute: false
      )
      brief!(lead, action, reading, estimate, version, type)
      reply!(I18n.t("assistant.requests.drafted"), kind: "request_reply",
                                                   title: I18n.t("assistant.requests.reply_title", subject: topic.subject.truncate(40)))
      action
    end

    def description(reading)
      criteria = Array(reading["acceptance"]).compact_blank.map { "- [ ] #{it}" }
      [reading["description"].to_s,
       ("**#{I18n.t('assistant.requests.acceptance')}**\n#{criteria.join("\n")}" if criteria.any?),
       I18n.t("assistant.requests.from_forum", link: "[#{topic.subject}](#{topic_url})")].compact_blank.join("\n\n")
    end

    def suggested_version
      project.shared_versions.where(status: "open").where.not(effective_date: nil).order(:effective_date)
             .detect { Assistant::Facts::VersionReadiness.new(it).slip_days.zero? }
    end

    def type_for(kind)
      types = project.enabled_types.to_a
      wanted = kind == "bug" ? %w[bug 缺陷] : %w[feature 功能 user\ story 用户故事]
      types.find { |type| wanted.any? { type.name.downcase.include?(it) } } || types.first
    end

    def brief!(lead, action, reading, estimate, version, type)
      because = [
        "“#{Assistant::Text.plain(topic.content).truncate(120)}”",
        I18n.t("assistant.requests.brief.type", type: type&.name || "–"),
        *Array(reading["acceptance"]).first(4).map { I18n.t("assistant.requests.brief.criterion", text: it) },
        (estimate.hours ? estimate.because : nil),
        (version ? I18n.t("assistant.requests.brief.version", version: version.name) : nil)
      ].compact
      Assistant::Signal.offer!(
        detector: "forum_request", fingerprint: "message:#{topic.id}", recipient: lead, project:, subject: topic,
        action:, channel: "brief", state: "pending", score: 45, deliver_at: Time.current,
        payload: { "headline" => I18n.t("assistant.requests.brief.headline", subject: reading["subject"].truncate(80)),
                   "because" => because, "why_me" => I18n.t("assistant.requests.brief.why"), "nature" => "decision",
                   "options" => [{ "label" => I18n.t("assistant.requests.brief.create"), "action_id" => action.id }] }
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def remember(wp)
      FollowUp.create!(project:, place: topic, work_package: wp, asker: topic.author, told: ["recorded"])
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def news_for(follow_up, wp)
      version = Assistant::Facts.version_of(wp)
      if version&.closed? && !follow_up.told?("released")
        ["released", I18n.t("assistant.requests.released", ref: "##{wp.id}", version: version.name)]
      elsif Assistant::Facts.closed_status_ids.include?(wp.status_id) && !follow_up.told?("done")
        ["done", I18n.t("assistant.requests.done", ref: "##{wp.id}",
                                                   version: version ? I18n.t("assistant.requests.in_version", version: version.name) : "")]
      elsif !follow_up.told?("recorded")
        ["recorded", I18n.t("assistant.requests.recorded", ref: "##{wp.id}")]
      end
    end

    # In the standard level the assistant answers in public only with facts;
    # on behalf of nobody, so the reply is T2 unless a grant says otherwise
    # (03 §7). Replying in a topic someone asked in is what it is for, so the
    # team grants "request_reply" once and it becomes T1.
    def reply!(text, kind:, title:)
      Assistant::Actions::Propose.call(
        kind:, title:, steps: [{ "op" => "create_forum_reply",
                                 "attributes" => { "message_id" => topic.id, "content" => text } }],
        on_behalf_of: nil, project:, subject: topic, basis: [Assistant::Basis.for(topic)]
      )
    end

    def topic_url = Assistant::Provenance.message_url(topic, OpenProject::StaticRouting::StaticUrlHelpers.new)
  end
end
