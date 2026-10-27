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
      # A newly uploaded document says something about a matter the team has
      # already decided (04 D5 主动). Code finds the candidates: the file's
      # paragraphs that share the decision's own terms. Whether they agree is
      # for the person who uploaded it to judge, so the notice quotes both and
      # asks; it never claims a contradiction it cannot prove.
      class DocumentConflictsDecision < Base
        WINDOW = 3.days

        def candidates
          return [] unless Assistant::Facts::DocumentText.allowed?

          uploads.filter_map do |file|
            uploader = file.author
            next unless uploader.is_a?(User) && uploader.active? && !uploader.is_a?(AssistantUser)

            source = Assistant::Facts::DocumentText.new(viewer: uploader).of(file) or next
            matches = touching(source, uploader)
            next if matches.empty?

            candidate(
              fingerprint: "attachment#{file.id}", recipient: uploader, subject: file.container, nature: :decision,
              channel: "brief", certainty: :likely,
              headline: t("headline", file: file.filename.truncate(40), count: matches.size),
              because: matches.flat_map do |decision, passage|
                [t("decided", title: decision.title.truncate(50), quote: decision.quote.truncate(80),
                              by: decision.owner&.name || "–", on: day(decision.stated_at.to_date)),
                 t("file_says", quote: passage.truncate(120))]
              end,
              impact: { people: 1 }
            )
          end
        end

        private

        def uploads
          containers = { "Document" => ::Document.where(project:).select(:id),
                         "WorkPackage" => WorkPackage.where(project:).select(:id) }
          containers.flat_map do |type, ids|
            ::Attachment.where(container_type: type, container_id: ids, created_at: [since, WINDOW.ago].min..)
                        .where.not(author_id: nil).includes(:author).to_a
          end
        end

        # Each active decision whose terms the file repeats, with the
        # paragraph that repeats them most.
        def touching(source, viewer)
          paragraphs = source.text.split(/\n\s*\n/).map(&:squish).select { it.length >= 20 }
          return [] if paragraphs.empty?

          Assistant::Said.new(viewer).related_decisions(project, source.text.first(6000), limit: 3).filter_map do |decision|
            terms = Assistant::Text.terms("#{decision.title} #{decision.quote}")
            best = paragraphs.max_by { (Assistant::Text.terms(it) & terms).size }
            [decision, best] if (Assistant::Text.terms(best) & terms).size >= 2
          end
        end
      end
    end
  end
end
