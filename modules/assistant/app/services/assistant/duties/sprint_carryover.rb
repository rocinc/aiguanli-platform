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
  module Duties
    # The working day before a sprint ends: every open item gets a proposal —
    # carry it to the next sprint, move it back to the backlog — with the
    # reason the data shows (blocked, not started, almost done). Each is an
    # action; the delegator decides in the brief.
    class SprintCarryover < Base
      def self.due?(duty, now = Time.current)
        sprint = Assistant::Facts.current_sprint(duty.project, on: local(duty, now).to_date)
        return false unless sprint&.finish_date

        eve = Assistant::Facts.add_working_days(sprint.finish_date, -1)
        local(duty, now).to_date == eve && daily(duty, now, hour: 10)
      end

      def call
        sprint = Assistant::Facts.current_sprint(project, on: today)
        return Result.nothing("no_sprint") unless sprint

        following = Assistant::Facts.next_sprint(sprint)
        open = sprint.work_packages.where.not(status_id: Assistant::Facts.closed_status_ids).includes(:status, :assigned_to).to_a
        return Result.nothing("all_done") if open.empty?

        ids = open.map { triage(_1, sprint, following).id }
        Result.new(summary: "#{open.size}", action_ids: ids, produced: true)
      end

      # Why it is still open, and whether it is worth carrying: [reason, keep?].
      def self.reason_for(wp)
        blocked = Relation.where(to_id: wp.id, relation_type: "blocks").joins("JOIN work_packages b ON b.id = relations.from_id")
                          .where.not("b.status_id" => Assistant::Facts.closed_status_ids).exists?
        return [I18n.t("assistant.duties.sprint_carryover.blocked"), true] if blocked

        history = Assistant::Facts::History.new(wp)
        started = history.changes.any? { _1.attribute == "status_id" }
        return [I18n.t("assistant.duties.sprint_carryover.not_started"), false] unless started

        remaining = Assistant::Facts.remaining_hours(wp)
        [I18n.t("assistant.duties.sprint_carryover.in_progress", hours: Assistant::Text.hours(remaining), status: wp.status.name), true]
      end

      private

      def triage(wp, sprint, following)
        reason, keep = self.class.reason_for(wp)
        attributes = keep && following ? { "sprint_id" => following.id } : { "sprint_id" => nil }
        label = keep && following ? I18n.t("assistant.duties.sprint_carryover.carry", ref: "##{wp.id}", sprint: following.name)
                                  : I18n.t("assistant.duties.sprint_carryover.backlog", ref: "##{wp.id}")
        action = propose(kind: "sprint_carryover", subject: wp, title: label, auto_execute: false,
                         steps: [{ "op" => "update_work_package", "type" => "WorkPackage", "id" => wp.id, "attributes" => attributes }])
        offer(action, headline: I18n.t("assistant.duties.sprint_carryover.headline", ref: "##{wp.id} #{wp.subject.truncate(30)}", sprint: sprint.name),
                      because: [reason], subject: wp)
      end

    end
  end
end
