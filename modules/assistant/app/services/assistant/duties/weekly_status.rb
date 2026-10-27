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
    # Fridays at 16:00 (delegator's time): a draft of the project status —
    # suggested code with its reason, done this week, risks with a proposed
    # response, decisions needed — as an update_project_status action the
    # project manager edits or publishes (T2).
    class WeeklyStatus < Base
      CODES = %w[on_track at_risk off_track].freeze

      SYSTEM = <<~PROMPT
        You draft the weekly status of a project for its manager from the computed facts given.
        Return {"status_code": "on_track"|"at_risk"|"off_track", "explanation": "..."}.
        The explanation is plain text in the reader's language, with one short paragraph for each section:
        the reason for the status; done this week (with #ids); risks and the proposed response; decisions
        needed. Do not use Markdown markers such as **, #, or bullet symbols. Every sentence rests on a
        given fact and cites it (#id, number, version). Use the suggested status unless the facts clearly
        say otherwise. At most 120 words.
      PROMPT

      def self.due?(duty, now = Time.current) = weekly(duty, now, wday: (duty.scope.to_h["wday"] || 5).to_i, hour: (duty.scope.to_h["hour"] || 16).to_i)

      def call
        facts = material
        data = write(SYSTEM, facts)
        code = CODES.include?(data["status_code"]) ? data["status_code"] : facts[:suggested]
        text = data["explanation"].to_s.gsub("**", "").gsub(/^#+\s*/, "").strip
        return Result.nothing("empty") if text.blank?

        action = propose(kind: "weekly_status", title: I18n.t("assistant.duties.weekly_status.title", date: l(today)),
                         steps: [{ "op" => "update_project_status", "type" => "Project", "id" => project.id,
                                   "attributes" => { "status_code" => code, "status_explanation" => text } }],
                         subject: project, auto_execute: false)
        offer(action, headline: I18n.t("assistant.duties.weekly_status.headline", status: I18n.t("assistant.duties.weekly_status.codes.#{code}")),
                      because: facts[:reasons], subject: project)
        Result.new(summary: code, action_ids: [action.id], produced: true)
      end

      private

      def material
        week = (today - 6)..today
        closed = WorkPackage.where(project:, status_id: Assistant::Facts.closed_status_ids)
                            .where(updated_at: week.first.beginning_of_day..).map { "##{_1.id} #{_1.subject}" }
        versions = project.shared_versions.where(status: "open").where.not(effective_date: nil).order(:effective_date).first(3)
        readiness = versions.map { Assistant::Facts::VersionReadiness.new(_1) }.reject { _1.work_packages.empty? }
        burn = Assistant::Facts::BudgetBurn.new(project, viewer: delegator)
        overdue = WorkPackage.where(project:).where.not(status_id: Assistant::Facts.closed_status_ids).where(due_date: ...today)
        questions = Assistant::Intent.where(project:, kind: "question", status: "open").limit(8).map(&:title)
        suggested = suggest(readiness, burn, overdue)
        reasons = [*readiness.map(&:because), burn.because, (I18n.t("assistant.duties.weekly_status.overdue", count: overdue.count) if overdue.any?)].compact
        { suggested:, reasons:, closed_this_week: closed, versions: readiness.map(&:to_h), budget: burn.to_h.except("by_person"),
          overdue: overdue.limit(10).map { "##{_1.id} #{_1.subject} (due #{_1.due_date})" }, open_questions: questions,
          previous_status: project.status_code, sprint: (Assistant::Facts.current_sprint(project)&.then { Assistant::Facts::SprintFacts.new(_1).to_h.except("people") }) }
      end

      def suggest(readiness, burn, overdue)
        return "off_track" if readiness.any? { _1.slip_days > 3 }
        return "at_risk" if readiness.any?(&:at_risk?) || overdue.count > 2 || burn.ahead_of_progress.to_i > 10

        "on_track"
      end
    end
  end
end
