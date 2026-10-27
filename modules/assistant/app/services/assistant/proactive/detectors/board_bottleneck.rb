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
      # A board column that keeps holding work (04 A5): its cards have sat
      # there much longer than the rest of the board, or it is over its WIP
      # limit. Whoever runs the flow hears it with the oldest cards and what
      # holds each — an open blocker, the last word said — and a ready
      # question on the oldest one.
      class BoardBottleneck < Base
        MIN_DAYS = 3
        RATIO_PERCENT = 200

        def candidates
          flow = Assistant::Facts::BoardFlow.new(project, today:)
          columns = flow.columns.select { it.cards.size >= 2 }
          return [] if columns.size < 2

          stuck = columns.filter_map do |column|
            rest = median((columns - [column]).flat_map(&:cards).map(&:days))
            [column, rest] if stuck?(column, rest)
          end
          leads.flat_map { |lead| stuck.map { |column, rest| build(flow, column, rest, lead) } }
        end

        private

        def median(values) = values.sort[values.size / 2] || 0

        def stuck?(column, rest)
          column.over_limit? ||
            (column.median_days >= MIN_DAYS && column.median_days >= rest * RATIO_PERCENT.fdiv(100))
        end

        def build(flow, column, rest, lead)
          oldest = column.oldest
          candidate(
            fingerprint: "#{column.status.id}:#{today.cwyear}-#{today.cweek}", recipient: lead, subject: project, nature: :team,
            channel: "brief",
            headline: t("headline", column: column.status.name, count: column.cards.size, days: column.median_days),
            because: [(t("limit", limit: column.limit) if column.over_limit?),
                      t("compare", days: column.median_days, board: rest),
                      *oldest.map { line(it) }].compact,
            impact: { cascade: column.cards.size, people: column.cards.filter_map { it.work_package.assigned_to_id }.uniq.size },
            facts: { status_id: column.status.id, board_id: flow.board&.id, cards: column.cards.size, median_days: column.median_days },
            steps_for: ->(_user) { options(oldest) }
          )
        end

        def line(card)
          wp = card.work_package
          held = if card.blocked_by then t("blocked", ref: "##{card.blocked_by.id}", status: card.blocked_by.status.name)
                 elsif (said = Assistant::Facts::History.new(wp).comments.last) then t("said", quote: said["text"].truncate(50), on: said["on"])
                 else t("silent")
                 end
          t("card", ref: "##{wp.id}", subject: wp.subject.truncate(30), days: card.days, name: wp.assigned_to&.name || "–", held:)
        end

        def options(oldest)
          card = oldest.find { it.work_package.assigned_to.is_a?(User) } or return []
          wp = card.work_package
          [option(t("ask", ref: "##{wp.id}", name: wp.assigned_to.name), t("ask_consequence"), "ask_stuck",
                  [comment(wp, t("ask_comment", who: mention(wp.assigned_to), days: card.days, status: wp.status.name))])]
        end
      end
    end
  end
end
