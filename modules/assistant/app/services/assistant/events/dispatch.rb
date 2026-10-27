# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  module Events
    # Who called the assistant: a comment that mentions it, or a work package
    # handed to it; and who just joined a project. Each starts a job; the
    # journal or membership itself is never held up.
    module Dispatch
      module_function

      def subscribe!
        OpenProject::Notifications.subscribe(Assistant::Understanding::Extractor::EXTRACTED_EVENT) do |payload|
          read_changes(payload[:source], payload[:changes])
          read_signals(payload[:source], payload[:signals])
          Assistant::Understanding::Promises.for(payload[:items]) if enabled?(Assistant::Understanding::Sources.project_of(payload[:source]))
          Assistant::Proactive::Immediate.weigh_requests(payload[:items])
        rescue StandardError => e
          Rails.logger.error("[assistant] change reading failed: #{e.class} #{e.message}")
        end
        OpenProject::Notifications.subscribe(OpenProject::Events::JOURNAL_CREATED) do |payload|
          next unless payload[:trigger_callbacks]

          route(payload[:journal])
        rescue StandardError => e
          Rails.logger.error("[assistant] dispatch failed: #{e.class} #{e.message}")
        end
        OpenProject::Notifications.subscribe(OpenProject::Events::NEWS_COMMENT_CREATED) do |payload|
          called(payload[:comment], payload[:comment]&.comments)
        rescue StandardError => e
          Rails.logger.error("[assistant] dispatch failed: #{e.class} #{e.message}")
        end
        OpenProject::Notifications.subscribe(OpenProject::Events::TIME_ENTRY_CREATED) do |payload|
          called(payload[:time_entry], payload[:time_entry]&.comments)
        rescue StandardError => e
          Rails.logger.error("[assistant] dispatch failed: #{e.class} #{e.message}")
        end
        OpenProject::Notifications.subscribe(:"assistant.action_executed") do |payload|
          recorded(payload[:action])
        rescue StandardError => e
          Rails.logger.error("[assistant] follow-up failed: #{e.class} #{e.message}")
        end
      end

      def route(journal)
        return unless journal.is_a?(Journal) && journal.journable
        return if Assistant::Understanding::Sources.author_of(journal).is_a?(AssistantUser) || !enabled?(Assistant::Understanding::Sources.project_of(journal))

        words = journal_words(journal)
        Assistant::MentionJob.perform_later(journal, nil, Assistant::Called::Placeholder.post(journal)) if mentions_assistant?(words)
        Assistant::RequestJob.perform_later(journal.journable) if new_topic?(journal) && !mentions_assistant?(words)
        follow_up(journal)
        Assistant::AssignedJob.perform_later(journal) if journal.journable_type == "WorkPackage" && assigned_to_assistant?(journal)
      end

      # The product lead created the work package drafted from a forum topic.
      def recorded(action)
        return unless action&.kind == "request_draft" && action.subject.is_a?(::Message)

        wp = action.inverse.filter_map { WorkPackage.find_by(id: it["id"]) if it["type"] == "WorkPackage" }.first or return
        follow_up = Assistant::FollowUp.create_or_find_by!(place: action.subject, work_package: wp) do |record|
          record.project = action.project
          record.asker = action.subject.author
        end
        Assistant::Requests.new(action.subject).tell(follow_up)
      end

      def new_topic?(journal) = journal.journable.is_a?(::Message) && journal.initial? && journal.journable.parent_id.nil?

      # Work that came from a forum topic: say so there when it is done. A
      # release is noticed by the sweep (FollowUpJob), since versions keep
      # no journal.
      def follow_up(journal)
        return unless journal.journable.is_a?(WorkPackage) && journal.get_changes.key?("status_id")

        Assistant::Requests.follow_up!(journal.journable)
      end

      # Words written outside journals: a news comment, a time entry comment.
      def called(record, words, asker: nil)
        return unless callable?(record, words)

        Assistant::MentionJob.perform_later(record, asker)
      end

      def callable?(record, words)
        return false if record.nil? || Assistant::Understanding::Sources.author_of(record).is_a?(AssistantUser)

        enabled?(Assistant::Understanding::Sources.project_of(record)) && mentions_assistant?(words)
      end

      # A mention newly written into an agenda item's notes or into one of its
      # outcomes: the line saying it was heard appears under the item before the
      # answer does.
      def agenda_item_written(agenda_item)
        return unless agenda_item.saved_change_to_notes?
        return if mentions_assistant?(agenda_item.notes_before_last_save)

        called_in_meeting(agenda_item, agenda_item.notes, Assistant::Understanding::Sources.author_of(agenda_item))
      end

      def outcome_written(outcome)
        return unless outcome.saved_change_to_notes?
        return if mentions_assistant?(outcome.notes_before_last_save)

        called_in_meeting(outcome.meeting_agenda_item, outcome.notes, outcome.author)
      end

      def called_in_meeting(agenda_item, words, author)
        return unless callable?(agenda_item, words)

        asker = User.current.logged? ? User.current : nil
        who = asker || author
        return unless who.is_a?(User) && Assistant::Understanding::Sources.visible?(agenda_item, who)

        Assistant::Called::Placeholder.hold(agenda_item, who)
        called(agenda_item, words, asker:)
      end

      # Only what was newly written is a call: a work package comment or a
      # wiki edit note, a new forum post, a new news item.
      def journal_words(journal)
        case journal.journable
        when WorkPackage, ::WikiPage then journal.notes
        when ::Message then (journal.initial? ? journal.journable.content : nil)
        when ::News then (journal.initial? ? journal.journable.description : nil)
        end
      end

      # The reader has just read this text, including what it asks to
      # change on a work package; those changes become proposals here.
      def read_changes(source, changes)
        return if changes.blank?
        return if Assistant::Understanding::Sources.machine?(Assistant::Understanding::Sources.author_of(source))
        return unless enabled?(Assistant::Understanding::Sources.project_of(source))

        Assistant::Understanding::Proposals.for(source, changes)
      end

      def read_signals(source, signals)
        return if signals.blank?
        return if Assistant::Understanding::Sources.machine?(Assistant::Understanding::Sources.author_of(source))
        return unless enabled?(Assistant::Understanding::Sources.project_of(source))

        OpenProject::LocaleHelper.with_locale_for(Assistant::Understanding::Sources.author_of(source)) do
          Assistant::Understanding::Signals.for(source, signals)
        end
      end

      def enabled?(project) = project.present? && project.module_enabled?(:assistant)

      def mentions_assistant?(words)
        return false if words.blank?

        id = Assistant.user.id
        words.match?(/<mention[^>]*data-id="#{id}"[^>]*data-type="user"|<mention[^>]*data-type="user"[^>]*data-id="#{id}"/) ||
          words.match?(/(?<![\w@])@#{Regexp.escape(AssistantUser::LOGIN)}\b/o)
      end

      def assigned_to_assistant?(journal)
        return false if journal.initial? && journal.data.assigned_to_id != Assistant.user.id
        return journal.data.assigned_to_id == Assistant.user.id if journal.initial?

        previous = journal.previous
        journal.data.assigned_to_id == Assistant.user.id && previous&.data&.assigned_to_id != Assistant.user.id
      end
    end
  end
end
