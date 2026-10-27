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
  module Proactive
    module Detectors
      # A meeting said a work package moves ("这个延期一周", recorded by
      # the reader as a dated deferral or renegotiation) and three working
      # days later its dates still say otherwise. Told to the meeting's author
      # with the change ready to apply.
      class MeetingDecisionNotApplied < Base
        GRACE_WORKING_DAYS = 3

        def candidates
          items.filter_map do |item, wp|
            next unless item.said_due_on && wp.due_date && wp.due_date < item.said_due_on
            next if Assistant::Facts.working_days_between(item.stated_at.to_date + 1, today) < GRACE_WORKING_DAYS

            build(item, wp)
          end
        end

        private

        def items
          Assistant::Intent.live.where(project:, kind: %w[deferral commitment], strength: "firm")
                            .where(stated_at: 30.days.ago..).where.not(said_due_on: nil).includes(:source, :subject).filter_map do |item|
            wp = target(item)
            [item, wp] if wp && Assistant::Facts.open?(wp)
          end
        end

        def target(item)
          return item.subject if item.subject.is_a?(WorkPackage) && item.source.is_a?(MeetingAgendaItem)

          item.source.try(:work_package) if item.source.is_a?(MeetingAgendaItem)
        end

        def build(item, wp)
          meeting = item.source.meeting
          recipient = [meeting.author, *leads].find { it.is_a?(User) && it.active? } or return nil
          moved = Assistant::Facts.working_days_between(wp.due_date + 1, item.said_due_on)
          candidate(
            fingerprint: "#{item.id}:#{wp.due_date}", recipient:, subject: wp, nature: :team,
            headline: t("headline", meeting: meeting.title, ref: "##{wp.id}", date: day(item.said_due_on)),
            because: [t("said", meeting: meeting.title, date: day(meeting.start_time.to_date), quote: item.quote.truncate(60)),
                      t("plan", ref: "##{wp.id}", due: day(wp.due_date))],
            impact: { critical_path: graph.slack(wp.id)&.<=(moved) || false, cascade: graph.downstream(wp.id).size, people: 2 },
            facts: { since: item.stated_at },
            steps_for: lambda do |_user|
              [option(t("apply", date: day(item.said_due_on)), t("apply_consequence"), "apply_meeting_decision",
                      [step(wp, shift(wp, moved))])]
            end
          )
        end
      end
    end
  end
end
