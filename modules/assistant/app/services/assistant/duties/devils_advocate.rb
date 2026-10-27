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
    # The strongest case against a plan, when the team asked for one (03 §6.3
    # 唱反调): the working day before a sprint starts, and when a version
    # with real scope is ten working days out. Facts first — load against
    # capacity, how this kind of work overran before, what is still
    # contested — then the model argues the other side from them. It goes on
    # the agenda of the meeting where the plan is made, for the delegator to
    # keep or drop.
    class DevilsAdvocate < Base
      SYSTEM = <<~PROMPT
        You are the team's devil's advocate. From the computed facts about a plan, make the strongest honest
        case that the plan will not work as stated. Return {"case": "Markdown"}: at most 5 bullet points,
        each one claim resting on a given fact (cite #ids and numbers), most damaging first, then one line
        "What would change my mind:" with the cheapest check. No hedging, no invented facts, no blame on people.
      PROMPT
      VERSION_WORKING_DAYS = 10

      def self.due?(duty, now = Time.current) = daily(duty, now, hour: 9)

      def call
        plans = [sprint_plan, version_plan].compact
        ids = plans.filter_map { argue(*it) }
        ids.any? ? Result.new(summary: "#{ids.size}", action_ids: ids, produced: true) : Result.nothing
      end

      private

      def sprint_plan
        sprint = ::Sprint.where(project:).where(start_date: Assistant::Facts.next_working_day(today)).first if defined?(::Sprint)
        return unless sprint && sprint.work_packages.exists?

        facts = Assistant::Facts::SprintFacts.new(sprint).to_h
        [sprint, sprint.name, facts.merge("estimate_bias" => Assistant::Facts::EstimateBias.new(project, today:).to_h)]
      end

      def version_plan
        version = project.versions.where(status: "open").where.not(effective_date: nil).detect do
          Assistant::Facts.working_days_between(today + 1, it.effective_date) == VERSION_WORKING_DAYS
        end
        return unless version

        readiness = Assistant::Facts::VersionReadiness.new(version)
        return if readiness.open.size < 3

        contested = Assistant::Intent.where(project:, kind: "decision", status: "active", subject_type: "WorkPackage",
                                             subject_id: readiness.open.map(&:id)).select(&:contested?).map(&:title)
        [version, version.name, readiness.to_h.merge("contested_decisions" => contested,
                                                     "estimate_bias" => Assistant::Facts::EstimateBias.new(project, today:).to_h)]
      end

      def argue(plan, name, facts)
        return if Assistant::Signal.where(detector: "duty_devils_advocate", project:, subject: plan).exists?

        text = argument(facts)
        return if text.blank?

        meeting = planning_meeting(plan)
        steps = if meeting
                  [{ "op" => "create_meeting_agenda_item",
                     "attributes" => { "meeting_id" => meeting.id, "title" => I18n.t("assistant.duties.devils_advocate.agenda", plan: name),
                                       "notes" => text, "duration_in_minutes" => 10 } }]
                else
                  [{ "op" => "create_wiki_page",
                     "attributes" => { "project_id" => project.id, "title" => I18n.t("assistant.duties.devils_advocate.page", plan: name),
                                       "text" => text } }]
                end
        action = propose(kind: "devils_advocate", title: I18n.t("assistant.duties.devils_advocate.title", plan: name), steps:,
                         subject: plan, auto_execute: false)
        offer(action, headline: I18n.t("assistant.duties.devils_advocate.headline", plan: name),
                      because: text.lines.map(&:strip).grep(/\A[-*]/).first(3).map { it.sub(/\A[-*]\s*/, "") }, subject: plan)
        action.id unless action.status == "failed"
      end

      def argument(facts)
        return outline(facts) unless Assistant::Llm.configured? && !Assistant::Usage.near_budget?(project:)

        write(SYSTEM, facts, max_tokens: 6000)["case"].to_s.strip.presence || outline(facts)
      rescue Assistant::Llm::Error
        outline(facts)
      end

      # Without a model: the facts that argue against the plan, as they are.
      def outline(facts)
        lines = []
        if facts["capacity_hours"] && facts["remaining_hours"] && facts["remaining_hours"] > facts["capacity_hours"]
          lines << I18n.t("assistant.duties.devils_advocate.over", planned: facts["remaining_hours"], capacity: facts["capacity_hours"])
        end
        Array(facts["estimate_bias"]).each do |row|
          ratio = [row["duration_ratio"], row["hours_ratio"]].compact.max
          lines << I18n.t("assistant.duties.devils_advocate.bias", type: row["type"], ratio:) if ratio && ratio >= 1.3
        end
        lines << I18n.t("assistant.duties.devils_advocate.slip", days: facts["slip_working_days"]) if facts["slip_working_days"].to_i.positive?
        Array(facts["contested_decisions"]).each { lines << I18n.t("assistant.duties.devils_advocate.contested", title: it) }
        lines.map { "- #{it}" }.join("\n").presence
      end

      def planning_meeting(plan)
        by = plan.is_a?(::Version) ? plan.effective_date : plan.start_date
        ::Meeting.where(project:, template: false).where.not(state: %i[cancelled closed])
                 .where(start_time: now..by.end_of_day).order(:start_time).first
      end
    end
  end
end
