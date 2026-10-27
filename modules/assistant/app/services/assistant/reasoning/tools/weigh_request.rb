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
  module Reasoning
    module Tools
      # Should this person take on this request? Computes the facts (their
      # capacity and load up to the deadline, the usual effort for this kind of
      # work, what depends on it) and prepares the options as real, unexecuted
      # actions: say yes later, say yes and move something else, hand it to
      # someone with room, or decline.
      class WeighRequest < Base
        define "weigh_request",
               "Only for a request one person made of another (\"@Ada 能周三前帮忙验收一下吗\") when the person asked " \
               "wants to know whether to say yes. Returns capacity and load up to the deadline, the usual effort, " \
               "what depends on it, and options (accept / accept and move something / hand to someone with room / " \
               "decline) each prepared as an action. Not for questions about dates, schedules or versions.",
               { request_id: { type: "integer", description: "Id of the request as recorded from the conversation, if known" },
                 work_package: { type: "string", description: "The work package the request is about" },
                 text: { type: "string", description: "What is asked, e.g. \"验收全文检索\"" },
                 requester: { type: "string", description: "Who asked" },
                 person: { type: "string", description: "Who is asked; empty = the asking user" },
                 deadline: { type: "string", description: "YYYY-MM-DD the requester wants it by" } }

        def call(args)
          load_request(args)
          raise Refused, I18n.t("assistant.reasoning.errors.which_work_package") unless @subject

          facts = compute_facts
          options = build_options(facts)
          {
            "request" => { "text" => @text, "requester" => @requester&.name, "person" => @person.name,
                           "deadline" => iso(@deadline), "work_package" => wp_ref(@subject), "quote" => @quote },
            "facts" => facts.except(:alternate, :push),
            "options" => options.map { it.except("steps") },
            "cards" => [Cards.fact(I18n.t("assistant.reasoning.weigh.facts_title", person: @person.name), fact_card_rows(facts)),
                        Cards.options(I18n.t("assistant.reasoning.weigh.options_title"),
                                      options.map { it.slice("label", "consequence", "action_id") })]
          }
        end

        private

        def load_request(args)
          item = args["request_id"].present? ? Assistant::Intent.visible(user).find_by(id: args["request_id"]) : nil
          item ||= guess_item(args)
          @item = item
          @subject = args["work_package"].present? ? context.work_package(args["work_package"]) : item&.subject.presence
          @subject = nil unless @subject.is_a?(WorkPackage)
          @person = args["person"].present? ? context.person(args["person"]) : (item&.owner || user)
          @requester = args["requester"].present? ? context.person(args["requester"]) : (item&.counterparty || item&.source.try(:user))
          @requester = nil if @requester == @person
          @text = args["text"].presence || item&.title.to_s
          @quote = item&.quote
          @deadline = context.date(args["deadline"], default: item&.said_due_on) || Assistant::Facts.add_working_days(Date.current, 2)
          @deadline = Date.current if @deadline < Date.current
          @context = Context.new(user:, project: project || @subject&.project, subject: item&.source || @subject,
                                 conversation: context.conversation)
        end

        def guess_item(args)
          scope = Assistant::Intent.visible(user).live.where(kind: "commitment", strength: "requested")
          scope = scope.where(owner_id: context.person(args["person"]).id) if args["person"].present?
          scope = scope.where(subject: context.work_package(args["work_package"])) if args["work_package"].present?
          scope = scope.where(owner_id: user.id) if args["person"].blank? && args["work_package"].blank?
          scope.order(stated_at: :desc).first
        end

        def today = Date.current

        def compute_facts
          capacity = Assistant::Facts::Capacity.new(@person, today, @deadline)
          load = Assistant::Facts::Load.new(@person, today, @deadline, exclude: [@subject.id], today:)
          estimate = Assistant::Facts::Estimate.new(@subject.project, text: "#{@text} #{@quote}", subject: @subject)
          hours = estimate.hours || 2.0
          graph = Assistant::Facts::ScheduleGraph.new(@subject.project)
          sprint = Assistant::Facts.current_sprint(@subject.project)
          sprint_load = sprint && Assistant::Facts::Load.new(@person, today, sprint.finish_date, today:)
          {
            capacity: capacity.hours, capacity_because: capacity.because,
            committed: load.hours, free: load.free_hours, load_because: load.because,
            on_plate: load.entries.map do
              wp_ref(it.work_package).merge("hours_in_range" => it.hours_in_range, "due" => iso(it.due_date))
            end,
            estimate: hours, estimate_because: estimate.because, estimate_sufficient: estimate.sufficient?,
            shortfall: [(hours - load.free_hours).round(1), 0].max,
            fits_by_deadline: load.free_hours >= hours,
            earliest_fit: earliest_fit(hours),
            sprint: sprint && { "name" => sprint.name, "finish" => iso(sprint.finish_date),
                                "free_hours" => sprint_load.free_hours },
            subject_slack: graph.slack(@subject.id),
            subject_downstream: graph.downstream(@subject.id).filter_map { graph.nodes[it] }.map { "##{it.id} #{it.subject}" },
            subject_version: Assistant::Facts.version_of(@subject)&.then do
              { "name" => it.name, "date" => iso(it.effective_date) }
            end,
            alternate: alternate(hours),
            push: push_candidate(load, hours - load.free_hours)
          }.transform_keys(&:to_s)
        end

        def earliest_fit(hours)
          horizon = Assistant::Facts.add_working_days(today, 15)
          date = @deadline
          while date <= horizon
            return date if Assistant::Facts::Load.new(@person, today, date, exclude: [@subject.id], today:).free_hours >= hours

            date = Assistant::Facts.next_working_day(date)
          end
          nil
        end

        def alternate(hours)
          skip = [@person.id, @requester&.id].compact
          experts = Assistant::Facts::Expertise.new(@subject.project, "#{@subject.subject} #{@text}", viewer: user)
                                               .people(limit: 10).index_by { it.user.id }
          kind = Assistant::Facts::Estimate.kind_of("#{@text} #{@quote}")
          same_kind = Assistant::Facts::Estimate.new(@subject.project, text: @text, activity: kind)
          activity_hours = TimeEntry.where(project: @subject.project, activity_id: same_kind.activity_ids)
                                    .group(:user_id).sum(:hours)
          candidates = context.members.reject { skip.include?(it.id) }.filter_map do |member|
            free = Assistant::Facts::Load.new(member, today, @deadline, today:).free_hours
            next if free < hours

            score = experts[member.id]&.score.to_f + (activity_hours[member.id].to_f * 0.2)
            { "person" => member, "free" => free, "score" => score.round(1),
              "evidence" => [*experts[member.id]&.evidence,
                             (if activity_hours[member.id]
                                I18n.t("assistant.reasoning.weigh.did_kind", hours: activity_hours[member.id].round(1),
                                                                             activity: same_kind.to_h["activity"])
                              end)].compact.first(3) }
          end
          candidates.max_by { [it["score"], it["free"]] }
        end

        def push_candidate(load, shortfall)
          return nil unless shortfall.positive?

          graph = Assistant::Facts::ScheduleGraph.new(@subject.project)
          movable = load.entries.reject { it.work_package.id == @subject.id }.select { it.work_package.due_date }
          movable.select! do
            it.work_package.project == @subject.project && user.allowed_in_work_package?(:edit_work_packages, it.work_package)
          end
          movable.max_by { [graph.slack(it.work_package.id) || 999, it.hours_in_range] }&.work_package
        end

        def build_options(facts)
          options = []
          options << option_later(facts) if facts["earliest_fit"] || facts["fits_by_deadline"]
          options << option_push(facts) if facts["push"]
          options << option_alternate(facts) if facts["alternate"]
          options << option_decline(facts)
          letters = %w[A B C D E]
          options.each_with_index { |o, i| o["label"] = "#{letters[i]}. #{o['label']}" }
        end

        def reply_to_requester(key, **values)
          who = @requester ? StepBuilder.mention(@requester) : ""
          text = I18n.t("assistant.reasoning.weigh.replies.#{key}", who:, person: @person.name, text: @text, **values)
          { "op" => "comment", "as" => "person", "type" => "WorkPackage", "id" => @subject.id, "attributes" => { "notes" => text } }
        end

        def option_later(facts)
          date = facts["fits_by_deadline"] ? @deadline : facts["earliest_fit"]
          on_time = date <= @deadline
          consequence = if on_time
                          I18n.t("assistant.reasoning.weigh.consequences.on_time", free: facts["free"], hours: facts["estimate"])
                        else
                          I18n.t("assistant.reasoning.weigh.consequences.later", date: day(date), deadline: day(@deadline),
                                                                                 impact: impact_text(facts))
                        end
          steps = [reply_to_requester(on_time ? "accept" : "accept_later", date: day(date))]
          offer(on_time ? I18n.t("assistant.reasoning.weigh.labels.accept", date: day(date)) : I18n.t("assistant.reasoning.weigh.labels.accept_later", date: day(date)),
                consequence, "accept_request", steps)
        end

        def option_push(facts)
          moved = facts["push"]
          steps = [move_step(moved), reply_to_requester("accept", date: day(@deadline))].compact
          offer(I18n.t("assistant.reasoning.weigh.labels.accept_and_move", date: day(@deadline), ref: "##{moved.id}"),
                I18n.t("assistant.reasoning.weigh.consequences.move", ref: "##{moved.id} #{moved.subject}"),
                "accept_request_move", steps)
        end

        def move_step(wp)
          next_sprint = wp.sprint && Assistant::Facts.next_sprint(wp.sprint)
          attributes = if next_sprint
                         { "sprint_id" => next_sprint.id }
                       else
                         start = Assistant::Facts.next_working_day([@deadline, wp.start_date || @deadline].max)
                         span = [Assistant::Facts.working_days_between(wp.start_date || wp.due_date, wp.due_date), 1].max
                         { "start_date" => start.iso8601, "due_date" => Assistant::Facts.add_working_days(start, span - 1).iso8601 }
                       end
          if next_sprint && wp.due_date && wp.due_date <= (wp.sprint.finish_date || wp.due_date)
            span = [Assistant::Facts.working_days_between(wp.start_date || wp.due_date, wp.due_date), 1].max
            start = next_sprint.start_date || Assistant::Facts.next_working_day(@deadline)
            attributes.merge!("start_date" => start.iso8601,
                              "due_date" => Assistant::Facts.add_working_days(start,
                                                                              span - 1).iso8601)
          end
          { "op" => "update_work_package", "type" => "WorkPackage", "id" => wp.id, "attributes" => attributes }
        end

        def option_alternate(facts)
          alt = facts["alternate"]
          other = alt["person"]
          ask = I18n.t("assistant.reasoning.weigh.replies.ask_other", other: StepBuilder.mention(other), person: @person.name,
                                                                      text: @text, date: day(@deadline))
          steps = [{ "op" => "comment", "as" => "person", "type" => "WorkPackage", "id" => @subject.id, "attributes" => { "notes" => ask } },
                   reply_to_requester("handed_over", other: other.name)]
          offer(I18n.t("assistant.reasoning.weigh.labels.ask_other", other: other.name),
                I18n.t("assistant.reasoning.weigh.consequences.ask_other", other: other.name, free: alt["free"],
                                                                           evidence: alt["evidence"].join("；").presence || "–"),
                "hand_over_request", steps)
        end

        def option_decline(facts)
          reason = if facts["fits_by_deadline"]
                     I18n.t("assistant.reasoning.weigh.replies.reason_priority")
                   else
                     I18n.t("assistant.reasoning.weigh.replies.reason_full", committed: facts["committed"],
                                                                             capacity: facts["capacity"])
                   end
          offer(I18n.t("assistant.reasoning.weigh.labels.decline"),
                I18n.t("assistant.reasoning.weigh.consequences.decline"),
                "decline_request", [reply_to_requester("decline", reason:)])
        end

        def offer(label, consequence, kind, steps)
          action = ProposeTool.propose(@context, title: "#{label.sub(/\A[A-E]\. /, '')} · ##{@subject.id}", kind:, steps:,
                                                 quote: @quote, auto_execute: false)
          { "label" => label, "consequence" => consequence, "action_id" => action.id, "tier" => action.tier,
            "status" => action.status, "error" => action.error, "steps" => steps }.compact
        end

        def impact_text(facts)
          if facts["subject_downstream"].any? || facts["subject_slack"]
            I18n.t("assistant.reasoning.weigh.consequences.impact", slack: facts["subject_slack"] || "–",
                                                                    downstream: facts["subject_downstream"].first(3).join("、").presence || "–")
          else
            I18n.t("assistant.reasoning.weigh.consequences.no_impact")
          end
        end

        def day(date) = date && Assistant::Text.day(date)

        def fact_card_rows(facts)
          [
            [I18n.t("assistant.reasoning.weigh.rows.capacity"), "#{facts['capacity']} h", facts["capacity_because"]],
            [I18n.t("assistant.reasoning.weigh.rows.committed"), "#{facts['committed']} h", facts["load_because"]],
            [I18n.t("assistant.reasoning.weigh.rows.free"), "#{facts['free']} h", nil],
            [I18n.t("assistant.reasoning.weigh.rows.estimate"), "#{facts['estimate']} h", facts["estimate_because"]],
            [I18n.t("assistant.reasoning.weigh.rows.dependency"), impact_text(facts), nil]
          ]
        end
      end
    end
  end
end
