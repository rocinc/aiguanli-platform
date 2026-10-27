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
  # Whether the assistant is still reading a comment its author just wrote,
  # and what it took from it once done. The state is the reader's own record
  # (the extraction of that journal), so "reading" is never shown
  # for a comment nobody is going to read.
  class Reading
    FRESH_FOR = 3.minutes
    GIVE_UP_AFTER = 2.minutes

    def initialize(journal:, user:, now: Time.current)
      @journal = journal
      @user = user
      @now = now
    end

    attr_reader :journal, :user, :now

    def applicable?
      journal.user_id == user.id && journal.notes.present? && journal.created_at > now - FRESH_FOR &&
        journal.journable.is_a?(WorkPackage) && read_at_all?
    end

    def state
      return :none unless applicable?
      return :reading if reading?

      noted.any? ? :noted : :nothing
    end

    def reading?
      return false if journal.created_at < now - GIVE_UP_AFTER - delay

      extraction_pending? || mention_pending?
    end

    def noted = @noted ||= intents + assistant_actions

    def intents
      Assistant::Intent.where(source: journal).where.not(strength: "trivial").to_a
    end

    def assistant_actions
      Assistant::Action.where("basis @> ?", [{ gid: journal.to_gid.to_s }].to_json)
                       .where(created_at: journal.created_at..).to_a.select { _1.visible_to?(user) }
    end

    def extraction
      @extraction ||= Assistant::Extraction.where(source: journal).order(:id).last
    end

    private

    def extraction_pending?
      reads? && (extraction.nil? || extraction.status == "pending")
    end

    def read_at_all?
      return false unless Assistant::Surface.available?(journal.journable.project, user) || reads?

      reads? || mentions_assistant?
    end

    def reads? = Assistant::Understanding::Capture.capturable_journal?(journal)

    def mentions_assistant? = Assistant::Events::Dispatch.mentions_assistant?(journal.notes)

    def mention_pending?
      mentions_assistant? && !journal.journable.journals.where(user: Assistant.user).where(created_at: journal.created_at..).exists?
    end

    def delay = Assistant::Understanding::Capture::FIRST_READ_DELAY
  end
end
