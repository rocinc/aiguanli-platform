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
      # Someone was asked for a favour in a comment (06 M6). The person asked,
      # about to answer, sees what saying yes before the date would cost them,
      # with the two ways out that need no refusal: a date that fits, or
      # someone with room. Only when the usual effort for this kind of work is
      # known from time already logged here, and the time left falls short.
      class RequestWeigh < Base
        HORIZON_WORKING_DAYS = 15

        def candidates
          Assistant::Intent.live.where(project:, kind: "commitment", strength: "requested", stated_at: since..)
                           .includes(:owner, :counterparty, :subject).filter_map do |item|
            wp = item.subject
            next unless wp.is_a?(WorkPackage) && Assistant::Facts.open?(wp) && human?(item.owner)

            weigh(item, wp)
          end
        end

        private

        def weigh(item, wp)
          owner = item.owner
          deadline = item.said_due_on || wp.due_date
          return unless deadline

          deadline = [deadline, today].max
          estimate = Assistant::Facts::Estimate.new(project, text: "#{item.title} #{item.quote}", subject: wp)
          return unless estimate.sufficient? && estimate.hours

          load = Assistant::Facts::Load.new(owner, today, deadline, exclude: [wp.id], today:)
          over = (estimate.hours - load.free_hours).round(1)
          build(item, wp, deadline, estimate, load, over) if over.positive?
        end

        def build(item, wp, deadline, estimate, load, over)
          asker = item.counterparty if human?(item.counterparty)
          candidate(
            fingerprint: "intent:#{item.id}", recipient: item.owner, subject: wp, nature: :decision, channel: "inline",
            waiting: asker,
            headline: t("headline", title: item.title.truncate(16), date: day(deadline), hours: Assistant::Text.hours(over)),
            because: [t("asked", name: asker&.name || t("someone"), quote: item.quote.to_s.truncate(60)),
                      (load.because if load.entries.any?), estimate.because, t("short", need: Assistant::Text.hours(estimate.hours), free: Assistant::Text.hours([load.free_hours, 0].max))].compact,
            impact: { people: 1 }, facts: { need: estimate.hours, free: load.free_hours, over:, intent_id: item.id },
            steps_for: ->(_user) { options(item, wp, asker, deadline, estimate.hours) }
          )
        end

        def options(item, wp, asker, deadline, need)
          who = asker ? mention(asker) : ""
          list = []
          if (fit = earliest_fit(item.owner, wp, need, deadline))
            list << option(t("later", date: day(fit)), t("later_consequence", date: day(fit)), "renegotiate", [])
                    .merge(reply_draft: t("later_reply", date: day(fit)))
          end
          if (found = free_member(today, deadline, need, except: [item.owner.id, asker&.id].compact))
            other, free = found
            list << option(t("pass_on", name: other.name), t("pass_on_consequence", name: other.name, free: Assistant::Text.hours(free)),
                           "request_alternate", [ask_step(item, wp, other, deadline)])
                    .merge(reply_draft: t("pass_on_comment", who:, other: mention(other), title: item.title.truncate(40)))
          end
          list
        end

        def ask_step(item, wp, other, deadline)
          text = t("ask_draft", other: mention(other), title: item.title.truncate(40), date: day(deadline))
          { "op" => "comment", "as" => "person", "type" => "WorkPackage", "id" => wp.id, "attributes" => { "notes" => text } }
        end

        def earliest_fit(owner, wp, need, from)
          limit = Assistant::Facts.add_working_days(today, HORIZON_WORKING_DAYS)
          date = Assistant::Facts.next_working_day(from)
          while date <= limit
            return date if Assistant::Facts::Load.new(owner, today, date, exclude: [wp.id], today:).free_hours >= need

            date = Assistant::Facts.next_working_day(date)
          end
        end
      end
    end
  end
end
