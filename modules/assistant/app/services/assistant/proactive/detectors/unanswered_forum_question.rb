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
  module Proactive
    module Detectors
      # A question in the forum that nobody answered for two working days
      # (04 D2 缺席). Whoever knows most about it is asked whether they would
      # answer; if the team's own record already holds the answer, the
      # assistant offers to answer with it, quoting where it comes from.
      class UnansweredForumQuestion < Base
        WORKING_DAYS = 2

        def candidates
          topics.filter_map do |topic|
            known = already_answered(topic)
            expert = known ? nil : who_knows(topic)
            recipient = expert || leads.first or next

            candidate(
              fingerprint: "topic#{topic.id}", recipient:, subject: topic, nature: known ? :opportunity : :object,
              channel: "brief", certainty: :fact,
              headline: t(known ? "headline_known" : "headline", subject: topic.subject.truncate(50),
                                                                 days: WORKING_DAYS),
              because: [t("asked", name: topic.author&.name || "–", on: day(topic.created_at.to_date),
                                   quote: Assistant::Text.plain(topic.content).truncate(80)),
                        if known then t("known", where: known[:where])
                        elsif expert then t("why_you", reason: expert_reason(topic, expert))
                        else t("nobody")
                        end],
              impact: { people: 2 },
              steps_for: ->(_user) { known ? [answer_option(topic, known)] : [ask_option(topic, expert)] }
            )
          end
        end

        private

        def since = Assistant::Facts.add_working_days(today, -WORKING_DAYS).end_of_day

        def topics
          return [] unless defined?(::Message)

          ::Message.joins(:forum).where(forums: { project_id: project.id }, parent_id: nil, replies_count: 0)
                   .where(created_at: 30.days.ago..since).where.not(author_id: Assistant.user.id)
                   .includes(:author, :forum).select { question?(it) }
        end

        def question?(topic)
          text = "#{topic.subject} #{Assistant::Text.plain(topic.content)}"
          text.match?(/[?？]|怎么|如何|为什么|能不能|是否|有没有|吗[\s。]|\b(how|why|what|when|can|does|is there)\b/i)
        end

        def topic_text(topic) = "#{topic.subject} #{Assistant::Text.plain(topic.content)}"

        # The team already answered this elsewhere: a decision on the same
        # thing, or a wiki page about it.
        def already_answered(topic)
          text = topic_text(topic)
          decision = Assistant::Said.new(topic.author, today:).related_decisions(project, text, limit: 1).first
          return { kind: :decision, record: decision, where: decision.title } if decision

          page = project.wiki&.pages&.find do
            Assistant::Text.overlap("#{it.title} #{Assistant::Text.plain(it.text).first(2000)}", text).first >= 0.5
          end
          page && { kind: :wiki, record: page, where: page.title }
        rescue StandardError
          nil
        end

        def experts(topic)
          @experts ||= {}
          @experts[topic.id] ||= Assistant::Facts::Expertise.new(project, topic_text(topic), viewer: topic.author || leads.first)
                                                          .people(limit: 3)
                                                          .reject { it.user == topic.author || !it.user.active? }
        end

        def who_knows(topic) = experts(topic).first&.user

        def expert_reason(topic, expert)
          experts(topic).find { it.user == expert }&.evidence&.first(2)&.join(I18n.t("assistant.card.separator")).presence ||
            t("knows_project")
        end

        def ask_option(topic, expert)
          return option(t("ask_lead"), t("ask_lead_consequence"), "forum_nudge", []) unless expert

          option(t("ask", name: expert.name), t("ask_consequence"), "forum_nudge",
                 [{ "op" => "create_forum_reply", "as" => "person",
                    "attributes" => { "message_id" => topic.id,
                                      "content" => t("ask_reply", who: mention(expert), asker: topic.author&.name, days: WORKING_DAYS) } }])
        end

        def answer_option(topic, known)
          option(t("answer"), t("answer_consequence"), "forum_answer",
                 [{ "op" => "create_forum_reply",
                    "attributes" => { "message_id" => topic.id, "content" => answer_text(known) } }])
        end

        def answer_text(known)
          record = known[:record]
          helpers = OpenProject::StaticRouting::StaticUrlHelpers.new
          case known[:kind]
          when :decision
            t("answer_decision", title: record.title, quote: record.quote, by: record.owner&.name || "–",
                                 on: day(record.stated_at.to_date))
          when :wiki
            t("answer_wiki", title: record.title, url: helpers.project_wiki_path(project, record))
          end
        end
      end
    end
  end
end
