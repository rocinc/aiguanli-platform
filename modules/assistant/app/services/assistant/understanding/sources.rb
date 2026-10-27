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
  module Understanding
    # Where people write to each other, and how to read each place: what was
    # said, by whom, about what, and the conversation it is part of. Work
    # package comments, forum posts, wiki edits with their edit note, news and
    # their comments, and time entry comments all come through here, so the
    # rest of the system reads every place the same way.
    module Sources
      THREAD_LIMIT = 12
      Turn = Data.define(:ref, :author, :at, :text)

      module_function

      # A journal that carries words someone wrote, as opposed to a field change.
      def journal_text?(journal)
        return false unless journal.is_a?(Journal) && journal.journable

        case journal.journable
        when WorkPackage then journal.notes.present?
        when ::Message then journal.initial? || journal.notes.present?
        when WikiPage then journal.notes.present? || journal.initial?
        when News then journal.initial?
        else false
        end
      end

      # The thing the words are about; ledger entries hang off it.
      def subject_of(record)
        case record
        when Journal then subject_of(record.journable)
        when ::Message then record.root
        when Comment then record.commented
        when TimeEntry then record.entity.is_a?(WorkPackage) ? record.entity : record.project
        when MeetingAgendaItem then record.meeting
        else record
        end
      end

      def project_of(record)
        subject = subject_of(record)
        subject.is_a?(Project) ? subject : subject.try(:project)
      end

      def author_of(record)
        case record
        # A forum post's journal is written by whoever is User.current when it
        # is saved, which need not be its author.
        when Journal then record.journable.is_a?(::Message) ? record.journable.author : record.user
        when TimeEntry then record.user
        when ::Message, Comment, WikiPage, News then record.author
        when MeetingAgendaItem then record.presenter || record.author || record.meeting.author
        end
      end

      def stated_at(record)
        record.is_a?(MeetingAgendaItem) ? (record.meeting.start_time || record.created_at) : record.created_at
      end

      # What the assistant itself wrote is not read back as someone's word.
      def machine?(user) = defined?(::AssistantUser) && user.is_a?(::AssistantUser)

      def internal?(record) = record.is_a?(Journal) && record.internal?

      # The words themselves, as plain text.
      def text_of(record)
        case record
        when Journal then journal_words(record)
        when Comment then Text.plain(record.comments)
        when TimeEntry then record.comments.to_s.strip
        when MeetingAgendaItem then Extractor.agenda_text(record)
        else ""
        end
      end

      def journal_words(journal)
        case journal.journable
        when WorkPackage then Text.plain(journal.notes)
        when ::Message
          message = journal.journable
          [(message.subject if message.parent_id.nil?), Text.plain(message.content)].compact_blank.join("\n")
        when WikiPage
          page = journal.journable
          note = Text.plain(journal.notes)
          journal.initial? ? [page.title, note, Text.plain(page.text).truncate(4000)].compact_blank.join("\n") : note
        when News
          news = journal.journable
          [news.title, news.summary, Text.plain(news.description)].compact_blank.join("\n")
        else ""
        end
      end

      # What came before in the same conversation, oldest first.
      def thread_of(record, limit: THREAD_LIMIT)
        turns = case record
                when Journal then journal_thread(record)
                when Comment then record.commented.comments.where(created_at: ...record.created_at).includes(:author)
                                        .reorder(created_at: :desc).limit(limit).to_a.reverse
                                        .map { turn("comment ##{_1.id}", _1.author, _1.created_at, Text.plain(_1.comments)) }
                else []
                end
        turns.last(limit)
      end

      def journal_thread(journal)
        case journal.journable
        when WorkPackage
          journal.journable.journals.where.not(notes: [nil, ""]).where(created_at: ...journal.created_at)
                 .reorder(created_at: :desc).limit(THREAD_LIMIT).includes(:user).to_a.reverse
                 .map { turn("comment ##{_1.id}", _1.user, _1.created_at, Text.plain(_1.notes)) }
        when ::Message
          message = journal.journable
          root = message.root
          [root, *root.children.where(created_at: ...message.created_at).reorder(created_at: :desc).limit(THREAD_LIMIT).to_a.reverse]
            .reject { _1.id == message.id }
            .map { turn("post ##{_1.id}", _1.author, _1.created_at, [_1.subject, Text.plain(_1.content)].compact_blank.join(": ")) }
        when WikiPage
          journal.journable.journals.where.not(notes: [nil, ""]).where(created_at: ...journal.created_at)
                 .reorder(created_at: :desc).limit(6).includes(:user).to_a.reverse
                 .map { turn("edit ##{_1.version}", _1.user, _1.created_at, Text.plain(_1.notes)) }
        else []
        end
      end

      def turn(ref, author, at, text) = Turn.new(ref:, author:, at:, text: text.to_s.truncate(800))

      # The place the reader should go to see the words.
      def kind_of(record)
        case record
        when Journal then record.journable_type.underscore
        when Comment then "news_comment"
        when TimeEntry then "time_entry"
        when MeetingAgendaItem then "meeting_agenda_item"
        end
      end

      def visible?(record, user)
        subject = subject_of(record)
        return false unless subject.respond_to?(:visible?) ? subject.visible?(user) : user.allowed_in_project?(:view_project, project_of(record))
        return record.visible?(user) if record.is_a?(Journal) && record.respond_to?(:visible?)

        true
      end
    end
  end
end
