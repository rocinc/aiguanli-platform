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
  module Understanding
    # A decision written down as a meeting outcome is already what the room
    # agreed on, so it becomes a ledger entry as typed, without the model.
    # Everything else said in the meeting is read once, after it is closed.
    module MeetingCapture
      VERSION = "meeting-outcome/1"
      READ_DELAY = 30.seconds

      module_function

      def subscribe!
        return if @subscribed

        @subscribed = true
        OpenProject::Notifications.subscribe(Extractor::EXTRACTED_EVENT) do |payload|
          next unless payload[:source].is_a?(MeetingAgendaItem)

          link_work_packages(payload[:source])
          UnownedItems.offer(payload[:source], payload[:items])
          RelatedDecision.offer(payload[:source])
        rescue StandardError => e
          Rails.logger.error("[assistant] unowned items not offered: #{e.class} #{e.message}")
        end
        OpenProject::Notifications.subscribe(:"assistant.action_executed") do |payload|
          ChecklistItems.offer(payload[:action])
          UnownedItems.taken(payload[:action])
        rescue StandardError => e
          Rails.logger.error("[assistant] meeting follow-up after action failed: #{e.class} #{e.message}")
        end
      end

      def outcome_saved(outcome)
        return unless enabled_for?(outcome)

        if outcome.decision_kind?
          record_decision(outcome)
        else
          drop_untouched(outcome)
          link_work_packages(outcome.meeting_agenda_item) if outcome.work_package_kind?
        end
        agenda_item_saved(outcome.meeting_agenda_item)
      end

      # While the meeting runs, an item where someone wrote something is read
      # again 30 seconds after the first save in a window; the job reads what
      # is there by then, so saves in between add no reading. An unchanged
      # text is not read twice (the extractor is keyed on its digest).
      def agenda_item_saved(agenda_item)
        meeting = agenda_item&.meeting
        return unless meeting&.in_progress? && !agenda_item.in_backlog? && Capture.enabled_for?(meeting.project)
        return unless written?(agenda_item) && !Assistant::Usage.near_budget?(project: meeting.project)
        return unless Rails.cache.write("assistant/meeting-read/#{agenda_item.id}", true, unless_exist: true,
                                                                                           expires_in: READ_DELAY - 5.seconds)

        ExtractJob.set(wait: READ_DELAY).perform_later(agenda_item)
      end

      def written?(agenda_item) = Text.plain(agenda_item.notes).present? || agenda_item.outcomes.exists?

      def outcome_destroyed(outcome)
        drop_untouched(outcome)
      end

      def meeting_closed(meeting)
        return unless Capture.enabled_for?(meeting.project)

        meeting.agenda_items.includes(:meeting_section).to_a.each do |agenda_item|
          next if agenda_item.in_backlog?
          next if agenda_item.title.blank? && agenda_item.notes.blank?

          ExtractJob.perform_later(agenda_item)
        end
      end

      def link_work_packages(agenda_item)
        outcomes = MeetingOutcome.where(meeting_agenda_item: agenda_item).includes(:work_package).to_a
        work_packages = outcomes.select(&:linked_work_package?).map(&:work_package)
        return if work_packages.empty?

        Intent.where(source: agenda_item).or(Intent.where(source: outcomes)).where(work_package_id: nil).find_each do |item|
          item.update!(work_package: work_packages.first)
        end
      end

      def enabled_for?(outcome)
        project = outcome.meeting_agenda_item&.meeting&.project
        project.present? && project.module_enabled?(:assistant)
      end

      def record_decision(outcome)
        quote = decision_quote(outcome)
        return drop_untouched(outcome) if quote.blank?

        agenda_item = outcome.meeting_agenda_item
        meeting = agenda_item.meeting
        item = Intent.find_or_initialize_by(source: outcome)
        return if item.persisted? && touched?(item)

        item.assign_attributes(
          project: meeting.project, kind: "decision", status: "active", strength: "firm",
          title: quote.truncate(200), quote:, subject: meeting,
          owner: outcome.author || agenda_item.presenter || agenda_item.author,
          stated_at: meeting.start_time || outcome.created_at, extractor_version: VERSION
        )
        item.save!
        link_work_packages(agenda_item)
        item
      end

      def decision_quote(outcome)
        Text.plain(outcome.notes).presence || outcome.meeting_agenda_item.title.to_s.strip
      end

      def drop_untouched(outcome)
        Intent.where(source_type: outcome.class.name, source_id: outcome.id).find_each do |item|
          item.destroy! unless touched?(item)
        end
      end

      def touched?(item)
        !item.live? || item.raised_objections.exists?
      end
    end
  end
end
