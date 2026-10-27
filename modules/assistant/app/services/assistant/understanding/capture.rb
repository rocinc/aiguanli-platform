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
    module Capture
      module_function

      # The person who wrote the comment should see what was understood while
      # they are still looking at it, so a new comment is read within seconds
      # instead of after the aggregation window. The aggregated pass afterwards
      # reads it again only if it was edited meanwhile (Extractor is keyed on
      # the text's digest).
      FIRST_READ_DELAY = 15.seconds

      def subscribe!
        OpenProject::Notifications.subscribe(OpenProject::Events::JOURNAL_CREATED) do |payload|
          journal = payload[:journal]
          next unless payload[:trigger_callbacks] && capturable_journal?(journal)

          ExtractJob.set(wait: FIRST_READ_DELAY).perform_later(journal)
        end

        [OpenProject::Events::AGGREGATED_WORK_PACKAGE_JOURNAL_READY,
         OpenProject::Events::AGGREGATED_MESSAGE_JOURNAL_READY,
         OpenProject::Events::AGGREGATED_WIKI_JOURNAL_READY,
         OpenProject::Events::AGGREGATED_NEWS_JOURNAL_READY].each do |event|
          OpenProject::Notifications.subscribe(event) do |payload|
            journal = payload[:journal]
            ExtractJob.perform_later(journal) if capturable_journal?(journal)
          end
        end

        OpenProject::Notifications.subscribe(OpenProject::Events::NEWS_COMMENT_CREATED) do |payload|
          comment = payload[:comment]
          ExtractJob.set(wait: FIRST_READ_DELAY).perform_later(comment) if capturable_record?(comment)
        end

        OpenProject::Notifications.subscribe(OpenProject::Events::TIME_ENTRY_CREATED) do |payload|
          entry = payload[:time_entry]
          ExtractJob.set(wait: FIRST_READ_DELAY).perform_later(entry) if capturable_record?(entry)
        end


      end

      def capturable_journal?(journal)
        Sources.journal_text?(journal) && !Sources.machine?(Sources.author_of(journal)) && !OwnWords.journal?(journal) &&
          enabled_for?(Sources.project_of(journal))
      end

      # A news comment or a time entry's comment: only when someone wrote
      # more than a word or two.
      def capturable_record?(record)
        return false unless record.is_a?(Comment) || record.is_a?(TimeEntry)
        return false if Sources.machine?(Sources.author_of(record))

        Sources.text_of(record).split.size >= 3 && enabled_for?(Sources.project_of(record))
      end

      def enabled_for?(project)
        project.present? && project.module_enabled?(:assistant) && Assistant::Llm.configured?
      end
    end
  end
end
