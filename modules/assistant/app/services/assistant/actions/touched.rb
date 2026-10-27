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
  module Actions
    # What a touched record is called to a person: the object the way the platform
    # names it ("#69 Knowledge base permissions", "v2.0", "9/21 Planning"), and
    # the few facts a sentence about it needs. Written into the preview while
    # the record still exists, because a preview rolls its records back.
    module Touched
      module_function

      TEXT_LIMIT = 80

      KINDS = { "Journal" => "comment", "Message" => "forum_reply", "Comment" => "news_comment",
                "Relation" => "relation", "MeetingAgendaItem" => "agenda_item", "MeetingOutcome" => "meeting_outcome",
                "UserNonWorkingTime" => "time_off", "RecurringMeeting" => "recurring_meeting",
                "Reminder" => "reminder", "TimeEntry" => "time_entry", "News" => "news",
                "WikiPage" => "wiki_page", "WorkPackage" => "work_package",
                "ResourceAllocation" => "resource_allocation", "GithubPullRequest" => "pull_request" }.freeze

      SPOKEN = %w[comment forum_reply news_comment].freeze

      def kind(record) = KINDS.fetch(record.class.name, "record")

      def label(record)
        case record
        when nil then ""
        when WorkPackage then "##{record.id} #{record.subject.truncate(50)}"
        when Journal then label(record.journable)
        when Relation then label(record.from)
        when Meeting then meeting(record)
        when ::Message then record.parent ? label(record.parent) : record.subject.to_s
        when ::Comment then record.commented.try(:title).to_s
        when MeetingAgendaItem then record.title.presence || meeting(record.meeting)
        when MeetingOutcome then label(record.meeting_agenda_item)
        when Reminder then label(record.remindable)
        when TimeEntry then label(record.entity)
        when GithubPullRequest then "PR ##{record.number}"
        else record.try(:name) || record.try(:title) || record.try(:subject) || record.class.model_name.human
        end.to_s
      end

      def anchor(record)
        case record
        when WorkPackage, Version, Project, Meeting, GithubPullRequest then record
        when Journal then record.journable
        when Relation then record.from
        when Reminder then record.remindable
        when TimeEntry then record.entity
        when MeetingAgendaItem then record.meeting
        when MeetingOutcome then record.meeting_agenda_item&.meeting
        else record.try(:entity)
        end
      end

      def detail(record)
        case kind(record)
        when "work_package" then { "type" => record.type&.name }
        when "comment" then { "text" => excerpt(record.notes), "internal" => record.restricted? }
        when "forum_reply" then { "text" => excerpt(record.content) }
        when "news_comment" then { "text" => excerpt(record.comments) }
        when "relation" then relation(record)
        when "agenda_item" then { "meeting" => meeting(record.meeting) }
        when "meeting_outcome" then { "text" => excerpt(record.notes) }
        when "time_off" then { "user" => record.user&.name, "from" => record.start_date.iso8601, "to" => record.end_date.iso8601 }
        when "recurring_meeting" then { "frequency" => record.frequency, "start" => record.start_time&.to_date&.iso8601 }
        when "reminder" then { "at" => record.remind_at&.iso8601 }
        when "time_entry" then { "user" => record.user&.name, "hours" => plain_number(record.hours), "on" => record.spent_on.iso8601 }
        when "resource_allocation" then allocation(record)
        when "pull_request" then { "number" => record.number, "title" => record.title.to_s.truncate(TEXT_LIMIT) }
        else {}
        end
      end

      def meeting(meeting)
        day = meeting.start_time && I18n.l(meeting.start_time.to_date, format: "%-m/%-d")
        [day, meeting.title].compact.join(" ")
      end

      def plain_number(number) = number.to_f.round(1).then { it % 1 == 0 ? it.to_i : it }

      def excerpt(markup) = Assistant::Text.plain(markup).squish.truncate(TEXT_LIMIT)

      def relation(record)
        { "relation" => record.relation_type, "target" => label(record.to) }
      end

      def allocation(record)
        { "user" => record.principal&.name, "hours" => plain_number(record.allocated_time.to_f / 60),
          "from" => record.start_date&.iso8601, "to" => record.end_date&.iso8601, "object" => label(record.entity) }
      end
    end
  end
end
