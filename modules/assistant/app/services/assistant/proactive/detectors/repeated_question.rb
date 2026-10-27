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
      # The same question asked the third time, by anyone, anywhere (03 §6.6,
      # 04 D4 模式). Its answers are already there; the assistant drafts the
      # FAQ entry from them and offers it to whoever answered most.
      class RepeatedQuestion < Base
        WINDOW = 180.days
        SAME = 0.5
        MIN_ASKED = 3

        def candidates
          clusters.filter_map do |questions|
            next if questions.size < MIN_ASKED
            next if covered_by_faq?(questions.first)

            answers = answers_to(questions)
            next if answers.empty?

            answerer = top_answerer(answers) or next
            candidate(
              fingerprint: "q#{questions.map(&:id).min}:#{questions.size}", recipient: answerer, subject: questions.last.subject,
              nature: :opportunity, channel: "brief", certainty: :fact,
              headline: t("headline", title: questions.first.title.truncate(50), count: questions.size),
              because: [*questions.last(3).map { asked_line(it) }, t("answered_by", count: answers.size)],
              impact: { people: questions.map(&:owner_id).uniq.size },
              steps_for: ->(_user) { [draft_option(questions, answers)] }
            )
          end
        end

        private

        def questions
          @questions ||= Assistant::Intent.where(project:, kind: "question").where(stated_at: WINDOW.ago..)
                                           .where.not(status: "dismissed").includes(:owner, :subject).order(:stated_at).to_a
        end

        # Questions grouped by what they ask: two belong together when most of
        # the shorter one's words are in the longer.
        def clusters
          groups = []
          questions.each do |question|
            group = groups.find { |members| members.any? { similar?(it, question) } }
            group ? group << question : groups << [question]
          end
          groups
        end

        def similar?(one, other)
          a = "#{one.title} #{one.quote}"
          b = "#{other.title} #{other.quote}"
          longer, shorter = a.length >= b.length ? [a, b] : [b, a]
          Assistant::Text.overlap(longer, shorter).first >= SAME
        end

        def answers_to(group)
          ids = Assistant::Intent.where(id: group.map(&:id), answered_by_type: "Journal").pluck(:answered_by_id)
          Journal.where(id: ids).includes(:user).to_a
        end

        def top_answerer(answers)
          answers.map(&:user).select { it.is_a?(User) && it.logged? && it.active? && !it.is_a?(AssistantUser) }.tally.max_by(&:last)&.first
        end

        def covered_by_faq?(question)
          page = project.wiki&.find_page(faq_title)
          page.present? && Assistant::Text.overlap(page.text.to_s, question.title).first >= SAME
        end

        def faq_title = I18n.t("assistant.proactive.repeated_question.page_title")

        def asked_line(question)
          t("asked", name: question.owner&.name || "–", on: day(question.stated_at.to_date), quote: question.quote.truncate(60))
        end

        def draft_option(group, answers)
          option(t("draft"), t("draft_consequence", page: faq_title), "faq_entry",
                 [{ "op" => "create_wiki_page",
                    "attributes" => { "project_id" => project.id, "title" => faq_title, "text" => faq_text(group, answers),
                                      "notes" => t("notes", title: group.first.title.truncate(60)) } }])
        end

        # Appended to the page as it is; the answers are quoted, not rewritten,
        # so the entry says nothing nobody said.
        def faq_text(group, answers)
          page = project.wiki&.find_page(faq_title)
          entry = ["## #{group.first.title}", "",
                   *answers.first(3).map { "> #{Assistant::Text.plain(it.notes).truncate(400)}\n> — #{it.user&.name}, #{day(it.created_at.to_date)}\n" },
                   t("sources", list: group.map { source_link(it) }.compact.join(", ")), ""].join("\n")
          [page&.text.presence || "# #{faq_title}\n", entry].join("\n\n")
        end

        def source_link(question)
          question.subject.is_a?(WorkPackage) ? "##{question.subject_id}" : question.subject.try(:title)
        end
      end
    end
  end
end
