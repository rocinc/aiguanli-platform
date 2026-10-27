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
      # The escalation ladder for something a person said they would do
      # (03 §4). It is the only reminder in projects where the
      # assistant is on.
      #
      #   stage 0  the working day before, only when their plan shows it is tight: their brief
      #   stage 1  the day itself, nothing has moved: one private ask, in their brief of the day
      #   stage 2  one working day late, still silent: the person waiting sees it in their brief, with a draft to ask
      #   stage 3  three working days late: the second and last private ask, in their brief
      #   then     nothing is pushed; the object shows the state, the next meeting lists it
      #
      # An ordinary promise scores below the interruption line, so stages 1 and 3 ride
      # the brief; on the critical path or when made to someone outside, they interrupt.
      #
      # Any answer from them — done, a new date, withdrawn, or just a comment
      # on the work package — starts the ladder again.
      class CommitmentLadder < Base
        def candidates
          Assistant::Intent.nudgeable.where(project:).where(said_due_on: ..Assistant::Facts.next_working_day(today))
                            .includes(:owner, :counterparty, :subject).flat_map { ladder(it) }
        end

        def self.stage_for(item, today)
          due = item.said_due_on
          return 0 if today < due
          return 1 if today == due

          late = Assistant::Facts.working_days_between(due + 1, today)
          return 2 if late.between?(1, 2)
          return 3 if late == 3

          nil
        end

        private

        def ladder(item)
          stage = self.class.stage_for(item, today)
          return [] if stage.nil? || !item.owner&.active?
          return [] if stage.zero? && !tight?(item)

          responded = last_response_at(item)
          return [] if responded && stage.positive? && responded.to_date >= item.said_due_on
          return [] if stage == 2 && item.counterparty.nil?

          fingerprint = "#{item.id}:#{item.said_due_on}:#{stage}:#{responded&.to_i}"
          stage == 2 ? [to_waiting(item, fingerprint)] : [to_owner(item, stage, fingerprint)]
        end

        def tight?(item)
          to = item.said_due_on
          load = Assistant::Facts::Load.new(item.owner, today, to, exclude: [item.subject_id], today:)
          remaining = item.subject.is_a?(WorkPackage) ? Assistant::Facts.remaining_hours(item.subject) : 0
          load.free_hours < [remaining, 2].max
        end

        def last_response_at(item)
          comments = item.subject.respond_to?(:journals) ? item.subject.journals.where(user_id: item.owner_id).where(created_at: item.stated_at..).maximum(:created_at) : nil
          [item.resolved_at, comments].compact.max
        end

        def to_owner(item, stage, fingerprint)
          wp = item.subject.is_a?(WorkPackage) ? item.subject : nil
          candidate(
            fingerprint:, recipient: item.owner, subject: item.subject, nature: :own,
            channel: stage.zero? ? "brief" : "notification",
            headline: t("owner_#{stage}", title: item.title.truncate(40), to: item.counterparty&.name || t("team"), due: day(item.said_due_on)),
            because: [t("said", quote: item.quote.truncate(60), on: day(item.stated_at.to_date)),
                      (Assistant::Facts::Load.new(item.owner, today, [item.said_due_on, today].max, today:).because if stage.zero?)].compact,
            impact: { people: item.counterparty ? 1 : 0, external: item.external_exposure, deadline: stage.positive?,
                      critical_path: (item.subject.is_a?(WorkPackage) && graph.slack(item.subject_id)&.<=(0)) || false },
            facts: { item_id: item.id, stage: },
            steps_for: ->(_user) { wp ? owner_options(item, wp) : [] }
          )
        end

        def owner_options(item, wp)
          new_due = Assistant::Facts.add_working_days([today, item.said_due_on].max, 2)
          [option(t("done"), t("done_consequence"), "commitment_done",
                  [comment(wp, t("done_comment", who: item.counterparty ? mention(item.counterparty) : "", title: item.title))]),
           option(t("renegotiate", date: day(new_due)), t("renegotiate_consequence"), "renegotiate",
                  [comment(wp, t("renegotiate_comment", who: item.counterparty ? mention(item.counterparty) : "", title: item.title, date: day(new_due))),
                   *(if wp.assigned_to_id == item.owner_id && wp.due_date && wp.due_date < new_due
                       [step(wp,
                             { "due_date" => new_due.iso8601 })]
                     else
                       []
                     end)])]
        end

        def to_waiting(item, fingerprint)
          wp = item.subject.is_a?(WorkPackage) ? item.subject : nil
          candidate(
            fingerprint:, recipient: item.counterparty, subject: item.subject, nature: :object, channel: "brief",
            headline: t("waiting", name: item.owner.name, title: item.title.truncate(40), on: day(item.stated_at.to_date)),
            because: [t("they_said", name: item.owner.name, quote: item.quote.truncate(60), on: day(item.stated_at.to_date)),
                      t("no_update")],
            impact: { people: 1 }, waiting: item.counterparty, facts: { item_id: item.id, stage: 2 },
            steps_for: lambda do |_user|
              next [] unless wp

              [option(t("ask", name: item.owner.name), t("ask_consequence"), "ask_owner",
                      [comment(wp, t("ask_comment", who: mention(item.owner), title: item.title))])]
            end
          )
        end
      end
    end
  end
end
