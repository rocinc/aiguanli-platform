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
  class IntentVerbs
    # Does one verb for one person: plans the steps, previews them, and either
    # hands back the draft to send, the preview to confirm, or the receipt.
    # Everything goes through Propose, so what a person may do is what they may
    # already do, and every change can be undone from its receipt.
    class Act
      Plan = Data.define(:kind, :title, :steps, :subject, :voice, :effects)
      Result = Data.define(:state, :action, :message, :trial)

      PARAMS = %i[meeting_id person_id target_id agenda_item_id text].freeze

      def initialize(verbs, verb, params = {}, confirm: false)
        @verbs = verbs
        @verb = verb.to_s
        @params = params.to_h.symbolize_keys.slice(*PARAMS)
        @confirm = confirm
      end

      attr_reader :verbs, :verb, :params

      delegate :intent, :user, :meeting, :project, to: :verbs

      def call
        return refuse("gone") unless verbs.verbs.include?(verb)
        return shelve if verb == "shelve"

        plan = build or return @refusal
        plan.voice == :person ? draft(plan) : run(plan)
      end

      def preview
        return refuse("gone") unless verbs.verbs.include?(verb)

        plan = build or return @refusal
        return draft(plan) if plan.voice == :person

        trial = trial_of(plan)
        trial.status == "failed" ? refuse_with(trial.error) : Result.new(state: :preview, action: nil, message: nil, trial:)
      end

      def self.unshelve(intent)
        intent.reopen! if intent.status == "dismissed"
      end

      private

      def shelve
        intent.settle!("dismissed")
        Result.new(state: :shelved, action: nil, message: nil, trial: nil)
      end

      def build
        plan = case verb
               when "schedule" then schedule
               when "assign" then assign
               when "remind" then remind
               when "answer", "record" then record
               end
        @refusal ||= refuse("gone") unless plan
        plan
      end

      def schedule
        target = verbs.schedule_targets.find { it.meeting.id == params[:meeting_id].to_i }
        return refusal("pick_meeting") unless target

        attributes = { "meeting_id" => target.meeting.id, "title" => intent.title.truncate(255), "notes" => agenda_notes,
                       "work_package_id" => verbs.work_package&.id }.compact
        Plan.new(kind: "intent_schedule", title: t("titles.schedule", meeting: target.meeting.title.truncate(60)),
                 steps: [{ "op" => "create_meeting_agenda_item", "attributes" => attributes }], subject: target.meeting,
                 voice: :assistant, effects: {})
      end

      def assign
        person = verbs.people.map(&:user).find { it.id == params[:person_id].to_i }
        return refusal("pick_person") unless person

        title = t("titles.assign", name: person.name)
        return assign_task(person, title) if intent.commitment_like?

        Plan.new(kind: "intent_assign", title:, steps: [words_step(text("assign", who: mention(person)))],
                 subject: verbs.place, voice: :person, effects: { "counterparty_id" => person.id })
      end

      def assign_task(person, title)
        work_package = verbs.work_package
        return refusal("already", name: person.name) if work_package&.assigned_to_id == person.id

        step = if work_package
                 { "op" => "update_work_package", "type" => "WorkPackage", "id" => work_package.id,
                   "attributes" => { "assigned_to_id" => person.id } }
               else
                 { "op" => "create_work_package",
                   "attributes" => { "project_id" => project.id, "subject" => intent.title.truncate(200),
                                     "assigned_to_id" => person.id, "due_date" => intent.said_due_on&.iso8601 }.compact }
               end
        Plan.new(kind: "intent_assign", title:, steps: [step], subject: work_package || project, voice: :assistant,
                 effects: { "owner_id" => person.id, "work_package" => work_package.nil? })
      end

      def remind
        target = verbs.remind_targets.find { it.id == params[:target_id].to_i } || verbs.remind_targets.first
        return refusal("gone") unless target

        Plan.new(kind: "intent_remind", title: t("titles.remind", name: target.name),
                 steps: [words_step(reminder_text(target))], subject: verbs.place, voice: :person, effects: {})
      end

      def record
        words = params[:text].to_s.strip
        return refusal("write_something") if words.blank?
        return decision_outcome(words) if intent.kind == "decision" || verbs.place.nil?

        asker = intent.owner if intent.owner && intent.owner != user
        words = "#{mention(asker)} #{words}" if asker
        Plan.new(kind: "intent_answer", title: t("titles.answer"), steps: [words_step(words)], subject: verbs.place,
                 voice: :person, effects: { "settle" => "answered" })
      end

      def decision_outcome(words)
        reason = verbs.outcome_reason
        return refusal("outcome_#{reason}") if reason

        item = verbs.agenda_items.find { it.id == params[:agenda_item_id].to_i } || verbs.agenda_items.first
        return refusal("no_agenda_item") unless item

        kind = intent.kind == "decision" ? "decision" : "information"
        effects = intent.kind == "decision" ? { "answered" => true } : { "settle" => "answered", "answered" => true }
        Plan.new(kind: "intent_record", title: t("titles.record"), subject: meeting, voice: :assistant, effects:,
                 steps: [{ "op" => "create_meeting_outcome", "attributes" => { "agenda_item_id" => item.id, "kind" => kind,
                                                                               "notes" => words } }])
      end

      def draft(plan)
        action = propose(plan)
        action.status == "failed" ? refuse_with(action.error) : Result.new(state: :draft, action:, message: nil, trial: nil)
      end

      def run(plan)
        trial = trial_of(plan)
        return refuse_with(trial.error) if trial.status == "failed"
        return Result.new(state: :preview, action: nil, message: nil, trial:) if trial.tier != "t1" && !@confirm

        action = propose(plan)
        return refuse_with(action.error) if action.status == "failed"

        Assistant::Decisions.new(action, user:).approve
        action.reload
        return refuse_with(action.error) unless action.executed?

        Effects.reconcile(intent)
        Result.new(state: :done, action:, message: nil, trial: nil)
      end

      def trial_of(plan)
        trial = nil
        ActiveRecord::Base.transaction(requires_new: true) do
          trial = propose(plan, remember: false)
          raise ActiveRecord::Rollback
        end
        trial
      end

      def propose(plan, remember: true)
        action = Assistant::Actions::Propose.call(
          kind: plan.kind, title: plan.title, steps: plan.steps, on_behalf_of: user, project:, subject: plan.subject,
          basis: basis, auto_execute: false
        )
        return action unless remember && action.status != "failed"

        action.update!(plan: action.plan.merge("intent" => { "id" => intent.id, "verb" => verb, "effects" => plan.effects }))
        action
      end

      def basis
        return [] unless Assistant::IntentVerbs.source_visible?(intent, user)

        source = intent.source
        source = source.meeting_agenda_item if source.is_a?(MeetingOutcome)
        [Assistant::Basis.for(source, quote: intent.quote)]
      end

      def agenda_notes
        return if basis.empty?

        sources = Assistant::Actions::SourceNote.sources_of(basis)
        return "> #{intent.quote.squish}" if sources.empty?

        Assistant::Actions::SourceNote.with_note(nil, sources)
      end

      def words_step(words)
        place = verbs.place
        if place.is_a?(::Message)
          { "op" => "create_forum_reply", "as" => "person", "attributes" => { "message_id" => place.id, "content" => words } }
        else
          { "op" => "comment", "as" => "person", "type" => "WorkPackage", "id" => place.id, "attributes" => { "notes" => words } }
        end
      end

      def reminder_text(target)
        who = mention(target)
        title = intent.title.truncate(60)
        work_package = verbs.work_package
        said = intent.said_due_on && Assistant::Text.day(intent.said_due_on)
        case intent.kind
        when "commitment" then commitment_reminder(who, title, work_package, said)
        when "deferral" then text("remind.deferral", who:, title:)
        when "decision" then text("remind.decision", who:, title:)
        else text("remind.question", who:, title:)
        end
      end

      def commitment_reminder(who, title, work_package, said)
        moved = work_package&.due_date && intent.said_due_on && work_package.due_date != intent.said_due_on
        if moved
          text("remind.commitment_moved", who:, title:, said:, ref: "##{work_package.id}",
                                          due: Assistant::Text.day(work_package.due_date))
        elsif said
          text("remind.commitment_dated", who:, title:, said:)
        else
          text("remind.commitment", who:, title:)
        end
      end

      def mention(person) = Assistant::Reasoning::StepBuilder.mention(person)

      def text(key, **) = I18n.t("assistant.verbs.words.#{key}", title: intent.title.truncate(60), **)

      def refusal(key, **)
        @refusal = refuse(key, **)
        nil
      end

      def refuse(key, **) = refuse_with(I18n.t("assistant.verbs.refused.#{key}", **))

      def refuse_with(message) = Result.new(state: :refused, action: nil, message:, trial: nil)

      def t(key, **) = I18n.t("assistant.verbs.#{key}", **)
    end
  end
end
