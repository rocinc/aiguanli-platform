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
      # In progress and untouched for five working days: one private question
      # to the assignee, with ready answers — still on it (new date), give it
      # back, or it is blocked.
      class Stalled < Base
        IN_PROGRESS = %w[进行中 in progress in_progress 开发中 doing].freeze
        IDLE_WORKING_DAYS = 5

        def candidates
          open_work_packages.select { in_progress?(it) && it.assigned_to.is_a?(User) }.filter_map do |wp|
            history = Assistant::Facts::History.new(wp, today:)
            idle = history.idle_working_days
            next unless idle && idle >= IDLE_WORKING_DAYS

            build(wp, idle, history)
          end
        end

        private

        def in_progress?(wp) = IN_PROGRESS.any? { wp.status.name.downcase.include?(it) }

        def build(wp, idle, history)
          owner = wp.assigned_to
          candidate(
            fingerprint: "#{wp.id}:#{history.last_activity_at.to_date}", recipient: owner, subject: wp, nature: :own,
            headline: t("headline", ref: "##{wp.id}", days: idle),
            because: [t("idle", days: idle, last: day(history.last_activity_at.to_date)),
                      (t("overdue", due: day(wp.due_date)) if wp.due_date && wp.due_date < today),
                      (t("critical", slack: graph.slack(wp.id)) if graph.slack(wp.id)&.<=(2))].compact,
            impact: { critical_path: graph.slack(wp.id)&.<=(2) || false, cascade: graph.downstream(wp.id).size },
            facts: { since: history.last_activity_at },
            steps_for: ->(user) { options(wp, user) }
          )
        end

        def options(wp, user)
          new_due = Assistant::Facts.add_working_days([today, wp.due_date || today].max, 3)
          list = [option(t("still_on_it", date: day(new_due)), t("still_on_it_consequence"), "renegotiate",
                         [step(wp, { "due_date" => new_due.iso8601 }.merge(wp.start_date && wp.start_date > new_due ? { "start_date" => new_due.iso8601 } : {})),
                          comment(wp, t("still_on_it_comment", date: day(new_due)))])]
          lead = leads.find { it != user }
          if lead
            list << option(t("give_back", name: lead.name), t("give_back_consequence"), "hand_back",
                           [step(wp, { "assigned_to_id" => nil }), comment(wp, t("give_back_comment", who: mention(lead)))])
          end
          list << option(t("blocked"), t("blocked_consequence"), "blocked",
                         [comment(wp, t("blocked_comment", who: lead ? mention(lead) : ""))])
          list
        end
      end
    end
  end
end
