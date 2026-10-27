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
  module Facts
    # The words in a document or an attachment, as the platform already extracted
    # them for full text search (04 D5). Nothing is read that the person may
    # not open, and nothing is read at all unless the administrator allowed
    # attachments to be read (the same switch the language model consent is).
    class DocumentText
      LIMIT = 40_000

      Source = Data.define(:record, :title, :text, :at, :author, :version) do
        def gid = record.to_gid.to_s
      end

      def self.allowed? = Setting.assistant_read_attachments? && Assistant::Llm.configured?

      def initialize(viewer:)
        @viewer = viewer
      end

      # One source per document (its description plus each attachment) or
      # per attachment, newest first.
      def of(record)
        case record
        when ::Document then document(record)
        when ::Attachment then attachment(record)
        end
      end

      # The previous upload with the same file name in the same container:
      # what "the earlier version" of a file means to people.
      def previous(attachment)
        ::Attachment.where(container: attachment.container, filename: attachment.filename)
                    .where(created_at: ...attachment.created_at).order(created_at: :desc).first
                    &.then { attachment(it) }
      end

      private

      def document(doc)
        return unless doc.visible?(@viewer)

        parts = [Assistant::Text.plain(doc.description)]
        parts.concat(doc.attachments.order(:id).filter_map do |file|
          text = fulltext(file)
          "## #{file.filename}\n#{text}" if text.present?
        end)
        Source.new(record: doc, title: doc.title, text: parts.compact_blank.join("\n\n").first(LIMIT),
                   at: doc.updated_at, author: nil, version: nil)
      end

      def attachment(file)
        return unless file.visible?(@viewer)

        text = fulltext(file)
        return if text.blank?

        Source.new(record: file, title: file.filename, text: text.first(LIMIT), at: file.created_at, author: file.author,
                   version: ::Attachment.where(container: file.container, filename: file.filename)
                                        .where(created_at: ..file.created_at).count)
      end

      def fulltext(file) = ::Attachment.where(id: file.id).pick(:fulltext).to_s.strip
    end
  end
end
