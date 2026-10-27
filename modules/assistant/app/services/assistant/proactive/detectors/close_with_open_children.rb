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
      # Someone closed a work package that still has open sub-tasks, an
      # unanswered question or a pull request not yet merged (04 A1 决策时刻).
      # Whoever closed it sees what is left, and can reopen it or close the
      # sub-tasks with it.
      class CloseWithOpenChildren < Base
        def candidates
          closed = Assistant::Facts.closed_status_ids
          events("work_package.updated").select do
            it.changed?("status_id") && closed.include?(it.after("status_id")) && !closed.include?(it.before("status_id"))
          end.filter_map do |event|
            wp = event.subject
            next unless wp.is_a?(WorkPackage) && human?(event.actor) && closed.include?(wp.status_id)

            left = left_open(wp, closed)
            build(event, wp, left) if left.values.any?(&:present?)
          end
        end

        private

        def left_open(wp, closed)
          { children: wp.children.where.not(status_id: closed).order(:id).to_a,
            questions: Assistant::Intent.live.where(project:, kind: "question", subject: wp).to_a,
            pulls: wp.respond_to?(:github_pull_requests) ? wp.github_pull_requests.where(state: "open", merged: false).to_a : [] }
        end

        def build(event, wp, left)
          parts = left.filter_map { |kind, list| t("part.#{kind}", count: list.size) if list.any? }
          candidate(
            fingerprint: event.journal_id.to_s, recipient: event.actor, subject: wp, nature: :decision, channel: "inline",
            headline: t("headline", ref: "##{wp.id}", list: parts.join(t("separator"))),
            because: [(t("children", list: left[:children].map { "##{it.id}" }.join(t("separator"))) if left[:children].any?),
                      (t("questions", list: left[:questions].map {
 it.title.truncate(40) }.join(t("separator"))) if left[:questions].any?),
                      (t("pulls", list: left[:pulls].map { "##{it.number}" }.join(t("separator"))) if left[:pulls].any?)].compact,
            impact: { people: 1 }, facts: { journal_id: event.journal_id, field: "status" },
            steps_for: ->(_user) { options(event, wp, left[:children]) }
          )
        end

        def options(event, wp, children)
          before = Status.find_by(id: event.before("status_id"))
          list = []
          if before
            list << option(t("reopen", status: before.name), t("reopen_consequence", ref: "##{wp.id}", status: before.name), "reopen_work",
                           [step(wp, { "status_id" => before.id })])
          end
          if children.any?
            list << option(t("close_children", list: children.map { "##{it.id}" }.join(t("separator"))),
                           t("close_children_consequence", status: wp.status.name), "close_children",
                           children.map { step(it, { "status_id" => wp.status_id }) })
          end
          list
        end
      end
    end
  end
end
