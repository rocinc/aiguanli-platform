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
  module Reasoning
    module Tools
      # The text of a document or an attached file, ready to summarise, to
      # turn into work packages, to write a test plan from, or to compare with
      # the earlier upload of the same file (04 D5). It returns the words and
      # what in the project they touch; the model writes, propose acts.
      class DocumentTool < Base
        define "document",
               "Read a document or attached file (needs the administrator's consent to read attachments). " \
               "Returns its text, the decisions and work packages it touches and, with compare=true, what " \
               "changed against the earlier upload of the same file. Use for summaries, extracting work " \
               "packages, test plans and requirement checks.",
               { document: { type: "string", description: "Document id or title" },
                 attachment: { type: "integer", description: "Attachment id, e.g. a file on a work package" },
                 compare: { type: "boolean", description: "Also return the diff against the earlier upload" } }

        def call(args)
          raise Refused, I18n.t("assistant.reasoning.errors.attachments_not_allowed") unless Assistant::Facts::DocumentText.allowed?

          record = find(args)
          source = facts.of(record) or raise Refused, I18n.t("assistant.reasoning.errors.not_found")
          result = { "title" => source.title, "kind" => record.class.name.underscore, "at" => iso(source.at.to_date),
                     "by" => source.author&.name, "upload" => source.version, "text" => source.text,
                     "decisions" => related_decisions(source.text), "work_packages" => related_work_packages(source.text) }
          result["changes"] = changes(record) if args["compare"] && record.is_a?(::Attachment)
          result.compact
        end

        private

        def facts = @facts ||= Assistant::Facts::DocumentText.new(viewer: user)

        def find(args)
          if args["attachment"].present?
            ::Attachment.find_by(id: args["attachment"]) || raise(Refused, I18n.t("assistant.reasoning.errors.not_found"))
          else
            ref = args["document"].to_s.strip
            documents = ::Document.visible(user).where(project:)
            documents.find_by(id: ref[/\A\d+\z/]) || documents.where("title ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(ref)}%").first ||
              raise(Refused, I18n.t("assistant.reasoning.errors.not_found"))
          end
        end

        def related_decisions(text)
          Assistant::Said.new(user).related_decisions(project, text.first(4000), limit: 6).map do
            { "title" => it.title, "quote" => it.quote, "on" => iso(it.stated_at.to_date), "by" => it.owner&.name }
          end
        end

        def related_work_packages(text)
          ids = text.scan(/#(\d+)/).flatten.map(&:to_i).uniq.first(20)
          WorkPackage.visible(user).where(id: ids).map { wp_ref(it) }
        end

        # Line by line against the earlier upload: what was added and removed,
        # so "what changed in v2 of the spec" is read off, not guessed.
        def changes(attachment)
          before = facts.previous(attachment) or return { "earlier" => nil }
          old_lines = lines(before.text)
          new_lines = lines(facts.of(attachment).text)
          { "earlier" => { "at" => iso(before.at.to_date), "by" => before.author&.name },
            "added" => (new_lines - old_lines).first(80), "removed" => (old_lines - new_lines).first(80) }
        end

        def lines(text) = text.to_s.lines.map(&:strip).compact_blank
      end
    end
  end
end
