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
  # One quiet line under a comment its author just posted: "reading…" while
  # the assistant reads, then what it noted, or nothing at all. It polls only
  # itself, and only while reading.
  class ReadingComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers
    include OpTurbo::Streamable

    POLL_MS = 2500
    RECEIPT_LIMIT = 2
    INTENT_LIMIT = 2

    def initialize(journal:, user:, reading: nil)
      super()
      @journal = journal
      @user = user
      @reading = reading || Reading.new(journal:, user:)
    end

    attr_reader :journal, :user, :reading

    def wrapper_uniq_by = journal.id

    def state = @state ||= reading.state

    def poll_url = url_helpers.assistant_journal_reading_path(journal)

    def noted_text
      count = reading.noted.size
      t("assistant.reading.noted", count:)
    end

    def receipts = @receipts ||= reading.assistant_actions.select(&:executed?).first(RECEIPT_LIMIT)

    def intent_line
      return @intent_line if defined?(@intent_line)

      @intent_line = if receipts.any? || proposals.any? || reading.intents.empty?
                       nil
                     else
                       sentences = reading.intents.first(INTENT_LIMIT).map { intent_sentence(_1) }
                       sentences << t("assistant.reading.more", count: reading.intents.size - INTENT_LIMIT) if reading.intents.size > INTENT_LIMIT
                       sentences.join(" ")
                     end
    end

    def generic_line? = receipts.empty? && proposals.empty? && intent_line.nil?

    def wrapper_data
      data = { test_selector: "assistant-reading", assistant_reading_state: state }
      return data unless state == :reading

      data.merge(controller: "assistant--reading", assistant__reading_url_value: poll_url,
                 assistant__reading_interval_value: POLL_MS)
    end

    def name = AssistantUser.instance.name

    def proposals
      return [] unless state == :noted

      @proposals ||= Assistant::SourceSignalsComponent.signals_for(journal, user)
    end

    private

    def intent_sentence(intent)
      return t("assistant.reading.noted_intent", title: intent.title) unless intent.commitment_like? && intent.said_due_on

      t("assistant.reading.noted_intent_due", title: intent.title, when: Assistant::Text.day(intent.said_due_on))
    end
  end
end
