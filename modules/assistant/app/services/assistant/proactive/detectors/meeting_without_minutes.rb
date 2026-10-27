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

module Assistant
  module Proactive
    module Detectors
      # A meeting ended over two hours ago and nothing records what was said:
      # no outcome written, no minutes page (03 §3.1, 04 B1). Its host gets an
      # outline of the minutes from the agenda and notes, as a wiki page to
      # confirm. Detectors ask no model; the meeting follow-up duty, where it
      # was handed over, writes the minutes in full and takes this over.
      class MeetingWithoutMinutes < Base
        AFTER = 2.hours
        WITHIN = 7.days

        def candidates
          return [] if Assistant::Duty.active.exists?(project:, kind: "meeting_followup")

          meetings.filter_map do |meeting|
            host = meeting.author
            next unless host.is_a?(User) && host.active? && !host.is_a?(AssistantUser)
            next if recorded?(meeting)

            build(meeting, host)
          end
        end

        private

        def meetings
          ::Meeting.not_templated.where(project:).where.not(state: ::Meeting.states[:cancelled])
                   .where("start_time + (interval '1 hour' * duration) BETWEEN ? AND ?", WITHIN.ago, AFTER.ago)
                   .includes(agenda_items: :outcomes)
        end

        def recorded?(meeting)
          meeting.agenda_items.any? { |item| item.outcomes.any? { it.notes.present? || it.work_package_id } } ||
            Assistant::Action.where(kind: "meeting_minutes", subject: meeting).exists? ||
            minutes_page?(meeting)
        end

        def minutes_page?(meeting)
          wiki = project.wiki or return false
          wiki.pages.where("title ILIKE ?", "%#{::WikiPage.sanitize_sql_like(meeting.title)}%")
              .where(created_at: meeting.start_time..).exists?
        end

        def build(meeting, host)
          candidate(
            fingerprint: meeting.id.to_s, recipient: host, subject: meeting, nature: :own, channel: "inline",
            headline: t("headline", meeting: meeting.title, date: day(meeting.start_time.to_date)),
            because: [t("ended", date: day(meeting.end_time.to_date), items: meeting.agenda_items.size), t("nothing")],
            impact: { people: meeting.participants.size },
            facts: { since: meeting.end_time, meeting_id: meeting.id },
            steps_for: ->(user) { options(meeting, user) }
          )
        end

        def options(meeting, user)
          text = OpenProject::LocaleHelper.with_locale_for(user) do
            Assistant::Duties::MeetingFollowup.outline(Assistant::Duties::MeetingFollowup.minutes_material(meeting))
          end
          [option(t("draft"), t("draft_consequence"), "meeting_minutes",
                  [Assistant::Duties::MeetingFollowup.minutes_step(meeting, text, user:)])]
        end
      end
    end
  end
end
