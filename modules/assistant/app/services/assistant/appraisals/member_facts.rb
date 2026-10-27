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
  module Appraisals
    # The raw record of one member in one project over a period, from which
    # every dimension is computed. Fairness corrections live here, next to the
    # numbers they correct: blocked time is taken off lateness, a date moved
    # before it was missed is the new date, firefighting is counted apart.
    class MemberFacts
      Delivery = Data.define(:work_package, :due, :closed_on, :late_days, :blocked_days, :renegotiated, :firefight)

      def initialize(user:, project:, from:, to:)
        @user = user
        @project = project
        @from = from
        @to = to
      end

      attr_reader :user, :project, :from, :to

      def deliveries
        @deliveries ||= closed_work_packages.filter_map do |wp|
          history = Assistant::Facts::History.new(wp)
          closed_on = closed_on(history) or next
          next unless (from..to).cover?(closed_on)

          due, renegotiated = effective_due(wp, history)
          blocked = blocked_days(wp, closed_on)
          late = due ? [Assistant::Facts.working_days_between(due + 1, closed_on) - blocked, 0].max : nil
          Delivery.new(work_package: wp, due:, closed_on:, late_days: late, blocked_days: blocked, renegotiated:,
                       firefight: firefight?(wp, history))
        end
      end

      # Times their work was moved from one sprint to the next in the period.
      def carried_over
        @carried_over ||= assigned_work_packages.sum do |wp|
          Assistant::Facts::History.new(wp).changes.count do |c|
            c.attribute == "sprint_id" && c.from.present? && c.to.present? && (from..to).cover?(c.at.to_date)
          end
        end
      end

      def reopened
        @reopened ||= assigned_work_packages.count do |wp|
          Assistant::Facts::History.new(wp).changes.any? do |c|
            c.attribute == "status_id" && closed?(c.from) && !closed?(c.to) && (from..to).cover?(c.at.to_date)
          end
        end
      end

      def hours_logged = @hours_logged ||= time_entries.sum(:hours).to_f.round(1)

      def hours_by_work_package = @hours_by_work_package ||= time_entries.where(entity_type: "WorkPackage").group(:entity_id).sum(:hours)

      def estimate_ratios
        deliveries.filter_map do |d|
          estimate = d.work_package.estimated_hours.to_f
          spent = hours_by_work_package[d.work_package.id].to_f
          (spent / estimate).round(2) if estimate.positive? && spent.positive?
        end
      end

      def commitments
        @commitments ||= Assistant::Intent.where(project:, owner: user, kind: %w[commitment deferral])
                                           .where(stated_at: from.beginning_of_day..to.end_of_day)
                                           .where.not(status: "dismissed").where.not(strength: %w[trivial requested]).to_a
      end

      def word_outcomes
        commitments.each_with_object(Hash.new(0)) do |item, tally|
          tally[word_outcome(item)] += 1
        end
      end

      def answered_for_others
        @answered_for_others ||= Assistant::Intent.where(project:, answered_by_type: "Journal",
                                                             answered_by_id: own_comments.select(:id))
                                                   .where.not(owner_id: user.id).count
      end

      def comments_on_others
        own_comments.joins("JOIN work_packages wp ON wp.id = journals.journable_id")
                    .where("wp.assigned_to_id IS DISTINCT FROM ?", user.id).count
      end

      def own_comments
        Journal.where(journable_type: "WorkPackage", journable_id: WorkPackage.where(project:).select(:id), user_id: user.id)
               .where.not(notes: [nil, ""]).where(created_at: from.beginning_of_day..to.end_of_day)
      end

      def meeting_items_taken
        Assistant::Intent.where(project:, owner: user, subject_type: "Meeting").where(stated_at: from.beginning_of_day..to.end_of_day).count
      end

      def depended_on_by
        open_ids = assigned_work_packages.map(&:id)
        Relation.where(relation_type: %w[blocks precedes], from_id: open_ids).count +
          Relation.where(relation_type: "follows", to_id: open_ids).count
      end

      # Comments on the work of people in their first month in the project.
      def helped_newcomers
        @helped_newcomers ||= begin
          joined = Member.where(project:).where.not(user_id: user.id).pluck(:user_id, :created_at).to_h
          own_comments.joins("JOIN work_packages wp ON wp.id = journals.journable_id").pluck("wp.assigned_to_id", "journals.created_at")
                      .count { |assignee, at| (since = joined[assignee]) && at.between?(since, since + 30.days) }
        end
      end

      def wiki_edits
        return 0 unless project.wiki

        Journal.where(journable_type: "WikiPage", journable_id: project.wiki.pages.select(:id), user_id: user.id)
               .where(created_at: from.beginning_of_day..to.end_of_day).count
      end

      # Defects that relate to or follow work they closed, opened in the period.
      def related_defects
        @related_defects ||= begin
          types = Assistant::Facts::SprintHistory::DEFECT_TYPES
          defect_types = Type.all.select { |type| types.any? { type.name.downcase.include?(it) } }.map(&:id)
          ids = closed_work_packages.map(&:id)
          linked = Relation.where(from_id: ids).pluck(:to_id) + Relation.where(to_id: ids).pluck(:from_id) +
                   WorkPackage.where(parent_id: ids).pluck(:id)
          WorkPackage.where(id: linked.uniq, type_id: defect_types).where(created_at: from.beginning_of_day..to.end_of_day).to_a
        end
      end

      # Check runs on pull requests linked to their work: [passed, finished].
      def check_runs
        @check_runs ||= if defined?(::GithubCheckRun)
                          runs = ::GithubCheckRun.joins(github_pull_request: :work_packages)
                                                 .where(work_packages: { id: assigned_work_packages.map(&:id) })
                                                 .where(completed_at: from.beginning_of_day..to.end_of_day).distinct
                          [runs.where(conclusion: "success").count, runs.where.not(conclusion: nil).count]
                        else
                          [0, 0]
                        end
      end

      # Working days from a question put to them to their answer, for the
      # questions that named them and that they answered.
      def response_days
        @response_days ||= Assistant::Intent.where(project:, kind: "question", counterparty_id: user.id)
                                             .where(stated_at: from.beginning_of_day..to.end_of_day).filter_map do |question|
          answered = Journal.where(id: question.answered_by_id, user_id: user.id).minimum(:created_at) if question.answered_by_type == "Journal"
          answered or next
          Assistant::Facts.working_days_between(question.stated_at.to_date + 1, answered.to_date)
        end
      end

      # Days on which they logged time on three or more different work packages.
      def switch_days
        @switch_days ||= time_entries.where(entity_type: "WorkPackage").group(:spent_on).distinct.count(:entity_id)
                                     .count { |_, count| count >= 3 }
      end

      def capacity = @capacity ||= Assistant::Facts::Capacity.new(user, from, [to, Date.current].min)

      def absent_days = capacity.absences.size

      private

      def time_entries = TimeEntry.where(project:, user:, spent_on: from..to)

      def assigned_work_packages
        @assigned_work_packages ||= WorkPackage.where(project:, assigned_to_id: user.id).includes(:status, :type).to_a
      end

      def closed_work_packages = assigned_work_packages.select { closed?(_1.status_id) }

      def closed?(status_id) = Assistant::Facts.closed_status_ids.include?(status_id)

      def closed_on(history)
        change = history.changes.reverse.find { _1.attribute == "status_id" && closed?(_1.to) }
        (change&.at || history.last_activity_at)&.to_date
      end

      # A due date moved later before it had passed is an honest early
      # renegotiation: the new date is the one that counts.
      def effective_due(wp, history)
        dues = history.changes.select { _1.attribute == "due_date" }
        due = dues.first&.from || dues.first&.to || wp.due_date
        renegotiated = false
        dues.each do |change|
          next if change.to.nil?

          if due.nil? || change.at.to_date <= due
            renegotiated ||= due.present? && change.to > due
            due = change.to
          end
        end
        [due, renegotiated]
      end

      def blocked_days(wp, closed_on)
        start = wp.start_date || closed_on
        blockers = Relation.where(to_id: wp.id, relation_type: %w[blocks precedes]).pluck(:from_id) +
                   Relation.where(from_id: wp.id, relation_type: "follows").pluck(:to_id)
        WorkPackage.where(id: blockers).filter_map do |blocker|
          finished = closed_on(Assistant::Facts::History.new(blocker)) || Date.current
          Assistant::Facts.working_days_between(start, [finished, closed_on].min) if finished > start
        end.max.to_i
      end

      def firefight?(wp, history)
        handed = history.changes.find { _1.attribute == "assigned_to_id" && _1.to == user.id && _1.from.present? }
        sprint = wp.sprint
        handed.present? && sprint&.start_date.present? && handed.at.to_date > sprint.start_date
      end

      def word_outcome(item)
        return "renegotiated" if item.moves.positive?
        return "withdrawn" if item.status == "withdrawn"
        return "kept" if item.status == "done" && (item.said_due_on.nil? || (item.resolved_at || Time.current).to_date <= item.said_due_on)
        return "late" if item.status == "done"
        return "open" if item.said_due_on.nil? || item.said_due_on >= Date.current

        "silent"
      end
    end
  end
end
