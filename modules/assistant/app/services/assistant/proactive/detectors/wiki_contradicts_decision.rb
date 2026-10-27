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
      # A wiki page still says what an earlier decision said, while a later
      # one replaced it (04 D4 矛盾). The page is found by the replaced
      # decision's own words in its text, so only pages that really repeat
      # it are touched. The page's last editor gets a drafted revision that
      # marks the passage and quotes the decision now in force.
      class WikiContradictsDecision < Base
        MIN_OVERLAP = 0.6

        def candidates
          return [] unless project.wiki

          superseded.flat_map do |old, current|
            pages_repeating(old).filter_map do |page|
              recipient = editor_of(page) or next
              candidate(
                fingerprint: "page#{page.id}:decision#{current.id}", recipient:, subject: page, nature: :object,
                channel: "inline", certainty: :fact,
                headline: t("headline", page: page.title.truncate(40), title: current.title.truncate(40)),
                because: [t("page_says", quote: old.quote.truncate(80)),
                          t("now", quote: current.quote.truncate(80), by: current.owner&.name || "–",
                                   on: day(current.stated_at.to_date))],
                impact: { people: 2 },
                steps_for: ->(_user) { [revise_option(page, old, current)] }
              )
            end
          end
        end

        private

        def superseded
          Assistant::Intent.where(project:, kind: "decision", status: "active").where.not(supersedes_id: nil)
                            .includes(:supersedes, :owner).filter_map { [it.supersedes, it] if it.supersedes }
        end

        def pages
          @pages ||= project.wiki.pages.includes(:author).to_a
        end

        def pages_repeating(old)
          words = old.quote.to_s
          return [] if words.length < 6

          pages.select do |page|
            text = Assistant::Text.plain(page.text)
            Assistant::Text.overlap(text, words).first >= MIN_OVERLAP && !page.text.to_s.include?(revision_marker(old))
          end
        end

        def editor_of(page)
          last = page.journals.reorder(version: :desc).includes(:user).first&.user
          [last, page.author].find { it.is_a?(User) && it.logged? && it.active? && !it.is_a?(AssistantUser) } || leads.first
        end

        def revision_marker(old) = "<!-- assistant:decision-#{old.id} -->"

        def revise_option(page, old, current)
          note = ["", revision_marker(old),
                  "> **#{t('note_title')}** #{t('note', title: current.title, by: current.owner&.name || '–',
                                                          on: day(current.stated_at.to_date))}",
                  "> “#{current.quote}”", ""].join("\n")
          option(t("revise"), t("revise_consequence"), "wiki_revision",
                 [{ "op" => "create_wiki_page",
                    "attributes" => { "project_id" => project.id, "title" => page.title, "text" => "#{page.text}\n#{note}",
                                      "notes" => t("notes", title: current.title.truncate(60)) } }])
        end
      end
    end
  end
end
