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
  module Facts
    # What happened to a work package: date changes (with who and when), the
    # number of times it was rescheduled, status moves, reassignments and the
    # last time anyone touched it.
    class History
      TRACKED = %w[start_date due_date status_id assigned_to_id estimated_hours sprint_id].freeze

      Change = Data.define(:at, :user, :attribute, :from, :to, :journal_id)

      def initialize(work_package, today: Date.current)
        @work_package = work_package
        @today = today
      end

      def changes
        @changes ||= journals.each_cons(2).flat_map do |before, after|
          TRACKED.filter_map do |attribute|
            was = before.data.try(attribute)
            now = after.data.try(attribute)
            next if was == now

            Change.new(at: after.created_at, user: after.user, attribute:, from: was, to: now, journal_id: after.id)
          end
        end
      end

      # A due date that moved later, by someone, after it was first set.
      def reschedules
        changes.select { it.attribute == "due_date" && it.from.present? && it.to.present? && it.to > it.from }
      end

      def last_activity_at = journals.last&.created_at

      # Days the assignee was away do not count: nobody was there to touch it.
      def idle_working_days
        last = last_activity_at&.to_date
        return unless last

        from = last + 1
        to = @today - 1
        absent = assignee_absences(from, to)
        (from..to).count { |day| Facts.working_day?(day) && absent.none? { it.cover?(day) } }
      end

      def entered_status_at
        status_change = changes.reverse.find { it.attribute == "status_id" }
        status_change&.at || @work_package.created_at
      end

      def to_h
        { "reschedules" => reschedules.map { describe(it) }, "reschedule_count" => reschedules.size,
          "changes" => changes.last(15).map { describe(it) },
          "last_activity" => last_activity_at&.to_date&.iso8601, "idle_working_days" => idle_working_days,
          "comments" => comments.last(8) }
      end

      def comments
        journals.select { it.notes.present? }.map do |j|
          { "journal_id" => j.id, "by" => j.user&.name, "on" => j.created_at.to_date.iso8601,
            "text" => Assistant::Text.plain(j.notes).truncate(300) }
        end
      end

      private

      def assignee_absences(from, to)
        assignee = @work_package.assigned_to
        return [] unless assignee.is_a?(User) && from <= to

        UserNonWorkingTime.where(user: assignee).overlapping(from..to).map(&:days)
      end

      def journals = @journals ||= @work_package.journals.includes(:user, :data).order(:version).to_a

      def describe(change)
        { "on" => change.at.to_date.iso8601, "by" => change.user&.name, "attribute" => change.attribute,
          "from" => label(change.attribute, change.from), "to" => label(change.attribute, change.to) }
      end

      def label(attribute, value)
        return nil if value.nil?

        case attribute
        when "status_id" then Status.find_by(id: value)&.name
        when "assigned_to_id" then Principal.find_by(id: value)&.name
        when "sprint_id" then Sprint.find_by(id: value)&.name
        when "start_date", "due_date" then value.to_date.iso8601
        else value
        end
      end
    end
  end
end
