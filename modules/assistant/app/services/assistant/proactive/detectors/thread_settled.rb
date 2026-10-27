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
      # A long discussion that has gone quiet after reaching a decision
      # (03 §6.6). The conclusion is drafted into the work package's
      # description, under its own heading, so the next reader does not have
      # to read forty comments. The words come from the decisions recorded in
      # the thread; nothing is summarised by guess.
      class ThreadSettled < Base
        MIN_COMMENTS = 12
        QUIET_WORKING_DAYS = 3

        def candidates
          WorkPackage.where(project:).where(id: long_threads.keys).includes(:assigned_to, :responsible).filter_map do |wp|
            decisions = settled(wp)
            next if decisions.empty? || summarised?(wp, decisions)

            recipient = Routing.owner_of(wp) or next
            candidate(
              fingerprint: "wp#{wp.id}:#{decisions.map(&:id).max}", recipient:, subject: wp, nature: :object, channel: "inline",
              certainty: :fact, headline: t("headline", ref: ref(wp), count: long_threads[wp.id]),
              because: [t("comments", count: long_threads[wp.id], days: QUIET_WORKING_DAYS),
                        *decisions.first(3).map { t("decided", title: it.title.truncate(60), by: it.owner&.name || "–") }],
              impact: { people: 1 },
              steps_for: ->(_user) { [summary_option(wp, decisions)] }
            )
          end
        end

        private

        def long_threads
          @long_threads ||= Journal.where(journable_type: "WorkPackage", journable_id: WorkPackage.where(project:).select(:id))
                                   .where.not(notes: [nil, ""]).where.not(user_id: Assistant.user.id)
                                   .group(:journable_id).having("COUNT(*) >= ?", MIN_COMMENTS)
                                   .having("MAX(journals.created_at) <= ?", quiet_since).count
        end

        def quiet_since = Assistant::Facts.add_working_days(today, -QUIET_WORKING_DAYS).beginning_of_day

        def settled(wp)
          Assistant::Intent.where(project:, subject: wp, kind: "decision", status: "active").includes(:owner).order(:stated_at).to_a
        end

        def heading = t("section")

        def summarised?(wp, decisions)
          text = wp.description.to_s
          text.include?(heading) && decisions.all? { text.include?(it.title) }
        end

        def summary_option(wp, decisions)
          section = ["## #{heading}", "",
                     *decisions.map { "- **#{it.title}** — #{it.owner&.name || '–'}, #{day(it.stated_at.to_date)}: “#{it.quote.truncate(160)}”" },
                     "", t("footer", count: long_threads[wp.id])].join("\n")
          description = wp.description.to_s.sub(/\n*## #{Regexp.escape(heading)}.*\z/m, "")
          option(t("write"), t("write_consequence"), "thread_summary",
                 [step(wp, "description" => [description.presence, section].compact.join("\n\n"))])
        end
      end
    end
  end
end
