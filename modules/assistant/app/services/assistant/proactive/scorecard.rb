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
    # The assistant's report card for one project (09 H2.5, constitution §10):
    # what it said in the last 30 days, what became of it, and what it kept
    # to itself. Every figure is about the assistant, none about a person.
    class Scorecard
      WINDOW = Feedback::WINDOW
      FIRST_WEEK = 7.days
      ADOPTED = Assistant::Signal::GOOD_OUTCOMES
      MIN_SAID = Feedback::RULE_SAMPLES
      MIN_LEAD = Feedback::MIN_SAMPLES
      HELD_WINDOW = 7.days
      HELD_SHOWN = 10
      HELD_REASONS = %w[uncertain early too_late cannot_act cold_start].freeze

      Rule = Data.define(:key, :said, :adopted, :muted, :demoted)
      Wrong = Data.define(:text, :url, :at)
      Held = Data.define(:label, :url, :reason, :at)
      Slipped = Data.define(:title, :due_on, :label, :url)
      Candour = Data.define(:promises, :comments) do
        def per_hundred
          (promises * 100.0 / comments).round(1) if comments >= MIN_COMMENTS
        end
      end
      MIN_COMMENTS = 20
      PROMISE_KINDS = %w[commitment deferral].freeze

      # What each step takes by hand, in minutes (03 §10 替人省下的时间).
      MINUTES_BY_OP = {
        "comment" => 3, "create_forum_reply" => 5, "create_news_comment" => 3, "update_work_package" => 2,
        "create_work_package" => 5, "create_relation" => 2, "create_time_entry" => 2, "create_non_working_time" => 2,
        "create_reminder" => 1, "update_version" => 3, "update_project_status" => 10, "create_resource_allocation" => 5,
        "create_wiki_page" => 20, "create_meeting_outcome" => 5, "create_meeting_agenda_item" => 3,
        "create_recurring_meeting" => 5, "create_work_breakdown" => 60, "publish_news" => 20
      }.freeze

      def initialize(project, user:, now: Time.current)
        @project = project
        @user = user
        @now = now
      end

      attr_reader :project, :user, :now

      def started_at
        return @started_at if defined?(@started_at)

        @started_at = Member.where(project:, principal: Assistant.user).minimum(:created_at)
      end

      def new_here? = started_at.nil? || started_at > now - FIRST_WEEK

      def said_count = @said_count ||= said.count

      def adopted_count = @adopted_count ||= said.where(outcome: ADOPTED).count

      def adoption_percent
        (adopted_count * 100.0 / said_count).round if said_count >= MIN_SAID
      end

      def wrong_count = @wrong_count ||= Feedback.false_alarms(project, since: now - WINDOW).values.sum

      def set_aside_count = outcome_count("rejected")

      def undone_count = outcome_count("undone")

      def muted_rules
        @muted_rules ||= (team_muted | personal_muted).select { known_rule?(it) }.sort
      end

      def rules
        @rules ||= rule_keys.map { rule(it) }.sort_by { [-it.said, it.key] }
      end

      def wrong
        @wrong ||= Assistant::Signal.where(project:, outcome: "wrong", outcome_at: window).order(outcome_at: :desc)
                                    .includes(:subject).filter_map do |signal|
          next unless visible?(signal)

          Wrong.new(text: signal.headline.to_s, url: url_for(signal.subject), at: signal.outcome_at)
        end
      end

      def wrong_hidden = wrong_count - wrong.size

      # Working days between a risk being told and the day it would have hurt.
      def lead_days
        @lead_days ||= begin
          days = lead_samples.filter_map { |act_by, created| lead_in_working_days(act_by, created.to_date) }
          { count: days.size, average: days.empty? ? nil : days.sum.fdiv(days.size).round(1) }
        end
      end

      def interruptions_per_person_day
        return @interruptions_per_person_day if defined?(@interruptions_per_person_day)

        people_days = Routing.people(project).size * working_days_observed
        @interruptions_per_person_day = people_days.zero? ? nil : interruptions_sent.fdiv(people_days).round(1)
      end

      # Firm promises that fell through while nothing had been said about their
      # object before the day they were due (03 §10 漏报).
      def missed
        @missed ||= Assistant::Intent.visible(user).where(project:, kind: PROMISE_KINDS, strength: "firm", status: %w[open done])
                                     .where(stated_at: (now - 180.days)..).includes(:work_package, :subject)
                                     .filter_map { missed_entry(it) }.sort_by { -it.due_on.to_time.to_i }
      end

      # How much of what people write still says who will do what by when,
      # this month against the one before. A fall means people have begun to
      # mind being on the record (N2).
      def candour = @candour ||= candour_in(window)

      def candour_before = @candour_before ||= candour_in((now - (2 * WINDOW))...(now - WINDOW))

      def candour_change
        now_value = candour.per_hundred
        before = candour_before.per_hundred
        return unless now_value && before

        if now_value < before * 0.8 then :fell
        elsif now_value > before * 1.2 then :rose
        else :steady
        end
      end

      def candour_gap = (candour_before.per_hundred - candour.per_hundred).abs

      def interruption_cap = Assistant::Preference.effective(nil, project).cap

      def minutes_saved
        @minutes_saved ||= Assistant::Action.where(project:, status: "executed", executed_at: window).pluck(:plan).sum do |plan|
          Array(plan["steps"]).sum { MINUTES_BY_OP.fetch(it["op"].to_s, 0) }
        end
      end

      def tokens = @tokens ||= Assistant::Usage.where(project:, created_at: window).tokens

      def held
        @held ||= Assistant::Signal.where(project:, created_at: (now - HELD_WINDOW)..now).order(created_at: :desc)
                                   .includes(:subject).filter_map { held_entry(it) }.first(HELD_SHOWN)
      end

      private

      def window = (now - WINDOW)..now

      def said = Assistant::Signal.where(project:, delivered_at: window)

      def working_days_observed
        Assistant::Facts.working_days_between([started_at || now, now - WINDOW].max.to_date, now.to_date)
      end

      def interruptions_sent = Assistant::Signal.where(project:, channel: "notification", delivered_at: window).count

      def candour_in(range)
        promises = Assistant::Intent.where(project:, kind: PROMISE_KINDS, stated_at: range).count
        written = Journal.where(created_at: range, journable_type: "WorkPackage").where.not(notes: [nil, ""])
        Candour.new(promises:, comments: written.where(journable_id: WorkPackage.where(project:).select(:id)).count)
      end

      def missed_entry(intent)
        object = work_package_of(intent)
        due = object&.due_date || intent.said_due_on
        return unless due_lately?(due) && slipped?(intent, object, due) && !warned?(object || intent.subject, due)

        Slipped.new(title: intent.title.to_s.squish.truncate(80), due_on: due, label: object_label(object), url: url_for(object))
      end

      def work_package_of(intent) = intent.work_package || (intent.subject if intent.subject.is_a?(WorkPackage))

      def due_lately?(due) = due.present? && due >= (now - WINDOW).to_date && due < now.to_date

      def warned?(subject, due)
        Assistant::Signal.exists?(project:, subject:, created_at: ((due - (2 * WINDOW)).beginning_of_day)...due.beginning_of_day)
      end

      def object_label(object) = object && "##{object.id} #{object.subject.to_s.truncate(30)}"

      def slipped?(intent, object, due)
        return true if object ? !object.closed? : intent.status == "open"

        intent.resolved_at.present? && intent.resolved_at.to_date > due
      end

      def team_muted = Array(Assistant::Preference.find_by(owner: project)&.muted_detectors)

      def personal_muted
        Assistant::Preference.where(owner: Routing.people(project)).flat_map { Array(it.muted_detectors) | it.muted_in(project) }
      end

      def outcome_count(outcome) = Assistant::Signal.where(project:, outcome:, outcome_at: window).count

      def known_rule?(key) = I18n.exists?("assistant.insights.detectors.#{key}.title")

      def rule_keys = (said_by_rule.keys | muted_rules | demoted_rules).select { known_rule?(it) }

      def demoted_rules = @demoted_rules ||= Feedback.demoted_detectors(project)

      def rule(key)
        Rule.new(key:, said: said_by_rule.fetch(key, 0), adopted: adopted_by_rule.fetch(key, 0),
                 muted: muted_rules.include?(key), demoted: demoted_rules.include?(key))
      end

      def said_by_rule = @said_by_rule ||= said.group(:detector).count

      def adopted_by_rule = @adopted_by_rule ||= said.where(outcome: ADOPTED).group(:detector).count

      def lead_samples
        Assistant::Signal.where(project:, created_at: window).where("payload #>> '{facts,act_by}' IS NOT NULL")
                         .pluck(Arel.sql("payload #>> '{facts,act_by}'"), :created_at)
      end

      def lead_in_working_days(act_by, told_on)
        due = Date.iso8601(act_by.to_s)
        [Assistant::Facts.working_days_between(told_on, due) - 1, 0].max if due >= told_on
      rescue Date::Error
        nil
      end

      def held_entry(signal)
        reason = (Array(signal.payload["gate"]) & HELD_REASONS).first
        return unless reason && visible?(signal)

        Held.new(label: label_for(signal), url: url_for(signal.subject), reason:, at: signal.created_at)
      end

      def label_for(signal)
        subject = signal.subject
        return signal.headline.to_s.truncate(40) unless subject.is_a?(WorkPackage)

        "#{subject.type&.name} ##{subject.id} #{subject.subject.to_s.truncate(30)}".strip
      end

      def url_for(subject)
        Rails.application.routes.url_helpers.work_package_path(subject) if subject.is_a?(WorkPackage)
      end

      def visible?(signal)
        subject = signal.subject
        case subject
        when nil then signal.subject_type.nil?
        when WorkPackage then visible_work_package_ids.include?(subject.id)
        when Project then subject == project
        else false
        end
      end

      def visible_work_package_ids = @visible_work_package_ids ||= WorkPackage.visible(user).where(project:).pluck(:id).to_set
    end
  end
end
