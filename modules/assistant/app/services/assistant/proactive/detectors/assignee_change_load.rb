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
      # Someone changed who a work package is assigned to (04 A1 决策时刻).
      # Whoever did it sees what the new assignee already has until the work
      # is due, and a promise the previous assignee had made about it, with
      # the change taken back, a person with room, or the promise passed on.
      class AssigneeChangeLoad < Base
        DEFAULT_WORKING_DAYS = 5

        def candidates
          events("work_package.updated").select {
 it.changed?("assigned_to_id") && it.after("assigned_to_id") }.filter_map do |event|
            wp = event.subject
            taker = User.find_by(id: event.after("assigned_to_id"))
            next unless wp.is_a?(WorkPackage) && Assistant::Facts.open?(wp) && human?(event.actor) && human?(taker) &&
                        wp.assigned_to_id == taker.id

            giver = User.find_by(id: event.before("assigned_to_id"))
            squeeze = squeeze_for(wp, taker)
            promise = promise_of(wp, giver)
            next unless squeeze || promise

            build(event, wp, taker, giver, squeeze, promise)
          end
        end

        private

        def squeeze_for(wp, taker)
          from = today
          to = wp.due_date && wp.due_date >= today ? wp.due_date : Assistant::Facts.add_working_days(today, DEFAULT_WORKING_DAYS)
          need = Assistant::Facts.remaining_hours(wp)
          load = Assistant::Facts::Load.new(taker, from, to, exclude: [wp.id], today:)
          over = (need - load.free_hours).round(1)
          { from:, to:, need:, load:, over: } if over.positive?
        end

        def promise_of(wp, giver)
          return unless human?(giver)

          Assistant::Intent.live.where(project:, kind: "commitment", subject: wp, owner: giver)
                           .where.not(strength: %w[trivial requested]).order(:stated_at).last
        end

        def build(event, wp, taker, giver, squeeze, promise)
          candidate(
            fingerprint: event.journal_id.to_s, recipient: event.actor, subject: wp, nature: :decision, channel: "inline",
            headline: headline(wp, taker, giver, squeeze, promise),
            because: [(t("load", name: taker.name, over: Assistant::Text.hours(squeeze[:over]), date: day(squeeze[:to])) if squeeze),
                      (squeeze[:load].because if squeeze&.dig(:load)&.entries&.any?),
                      (t("promise", name: giver.name, title: promise.title.truncate(60)) if promise)].compact,
            impact: { people: 1 }, facts: { journal_id: event.journal_id, field: "assignee" },
            steps_for: ->(_user) { options(wp, taker, giver, squeeze, promise) }
          )
        end

        def headline(wp, taker, giver, squeeze, promise)
          return t("headline_load", ref: "##{wp.id}", name: Assistant::Text.first_name(taker), over: Assistant::Text.hours(squeeze[:over]),
                                    date: day(squeeze[:to])) if squeeze

          t("headline_promise", ref: "##{wp.id}", taker: Assistant::Text.first_name(taker), name: Assistant::Text.first_name(giver))
        end

        def options(wp, taker, giver, squeeze, promise)
          list = []
          if human?(giver)
            list << option(t("revert", name: giver.name), t("revert_consequence", ref: "##{wp.id}", name: giver.name),
                           "revert_assignee", [step(wp, { "assigned_to_id" => giver.id })])
          end
          if squeeze && (found = free_member(squeeze[:from], squeeze[:to], squeeze[:need], except: [taker.id, giver&.id].compact))
            other, free = found
            list << option(t("another", name: other.name), t("another_consequence", name: other.name, free: Assistant::Text.hours(free)), "reassign",
                           [step(wp, { "assigned_to_id" => other.id })])
          end
          if promise
            list << option(t("tell", name: taker.name), t("tell_consequence", name: taker.name), "handover_promise",
                           [comment(wp, t("tell_comment", who: mention(taker), name: giver.name, title: promise.title.truncate(80)))])
          end
          list
        end
      end
    end
  end
end
