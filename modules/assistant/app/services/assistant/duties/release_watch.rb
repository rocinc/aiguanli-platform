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
    # Watches one version (scope "version_id") from T-14 working days: every
    # working morning its readiness goes to the delegator's brief, with the
    # same re-plan options the version checkpoint offers when it is at risk.
    # Once the version is closed, release notes are drafted from what was done,
    # for the delegator to edit and publish as news. The same goes for a phase
    # whose gate has been passed. Five working days before a release date or a
    # phase gate, a reminder to the outside addresses the duty lists is
    # drafted for the delegator to read and send (S8 channel 7).
    class ReleaseWatch < Base
      NOTES_LOOKBACK = 3.days
      PHASE_LOOKBACK_DAYS = 3
      EXTERNAL_LEAD_DAYS = 5
      PHASE_SYSTEM = <<~PROMPT
        You write a project news item about a project phase that has just been completed. Reply as JSON
        {"title": string, "summary": string, "description": string}.
        title: at most 80 characters. summary: one or two sentences. description: Markdown following the TEMPLATE.
        Use only the given facts; refer to work packages as #id; no praise, no people's names unless given.
      PROMPT

      NOTES_SYSTEM = <<~PROMPT
        You write a project news item from facts. Reply as JSON {"title": string, "summary": string, "description": string}.
        title: at most 80 characters. summary: one or two sentences. description: Markdown following the TEMPLATE.
        Use only the given facts; refer to work packages as #id; no praise, no people's names unless given.
      PROMPT

      def self.due?(duty, now = Time.current) = daily(duty, now, hour: 9)

      def call
        drafted = external_notices
        result = watch
        return result if drafted.empty?

        Result.new(summary: result.summary, action_ids: result.action_ids + drafted.map(&:id), produced: true)
      end

      private

      def watch
        notes = closed_versions.filter_map { release_notes(it) }
        notes += passed_phases.filter_map { phase_news(it) } unless scope["version_id"]
        return Result.new(summary: "release_notes", action_ids: notes.map(&:id), produced: true) if notes.any?

        version = watched_version
        return Result.nothing("no_version") unless version&.effective_date

        left = Assistant::Facts.working_days_between(today + 1, version.effective_date)
        return Result.nothing("not_yet") if left > 14 || left.negative?
        return Result.nothing("silenced") if silenced?

        readiness = Assistant::Facts::VersionReadiness.new(version)
        detector = Assistant::Proactive::Detectors::VersionCheckpoint.new(project, today:)
        options = readiness.at_risk? ? detector.options(version, readiness) : []
        actions = options.map do |option|
          propose(kind: option[:kind].to_s, title: option[:label], steps: option[:steps], subject: version, auto_execute: false)
        end
        signal_options = actions.zip(options).map { |action, option| { "label" => option[:label], "consequence" => option[:consequence], "action_id" => action.id } }
        Assistant::Signal.create!(
          detector: "duty_release_watch", fingerprint: "#{duty.id}:#{today}", recipient: delegator, project:, subject: version,
          channel: "brief", state: "pending", score: 0, deliver_at: now, action: actions.first,
          payload: { "headline" => I18n.t("assistant.duties.release_watch.headline", version: version.name, days: left,
                                                                                     done: readiness.done_ratio, open: readiness.open.size),
                     "because" => [readiness.because, *readiness.overdue.first(5).map { "##{_1.id} #{_1.subject}" }],
                     "why_me" => I18n.t("assistant.duties.why", duty: title), "options" => signal_options, "duty_id" => duty.id }
        )
        Result.new(summary: "T-#{left}", action_ids: actions.map(&:id), produced: true)
      rescue ActiveRecord::RecordNotUnique
        Result.nothing("already")
      end

      def watched_version
        Version.find_by(id: scope["version_id"]) || project.shared_versions.where(status: "open")
                                                          .where.not(effective_date: nil).order(:effective_date).first
      end

      def external_notices
        return [] if outside_addresses.empty? || silenced?

        [version_notice, *gate_notices].compact
      end

      def outside_addresses = scope["external_to"].to_s.split(/[\s,;]+/).grep(URI::MailTo::EMAIL_REGEXP).uniq

      def coming?(date) = date.present? && Assistant::Facts.working_days_between(today + 1, date).between?(0, EXTERNAL_LEAD_DAYS)

      def version_notice
        version = watched_version
        return unless version && version.status == "open" && coming?(version.effective_date)
        return if Assistant::Action.exists?(kind: "external_notice", project:, subject: version)

        work = WorkPackage.with_target_version(version.id)
        open = work.where.not(status_id: Assistant::Facts.closed_status_ids).count
        external_draft(
          version, date: version.effective_date,
                   subject: I18n.t("assistant.duties.release_watch.external.version_subject", project: project.name, name: version.name,
                                                                                              date: l(version.effective_date)),
                   body: I18n.t("assistant.duties.release_watch.external.version_body#{'_plain' if work.none?}", name: version.name,
                                                                                                          date: l(version.effective_date),
                                                                                                          total: work.count,
                                                                                                          done: work.count - open, open:),
                   because: [I18n.t("assistant.duties.release_watch.external.version_because", name: version.name, date: l(version.effective_date))]
        )
      end

      def gate_notices
        return [] if scope["version_id"] || !delegator.allowed_in_project?(:view_project_phases, project)

        project.phases.active.includes(:definition).select { it.finish_gate? && coming?(it.finish_date) }.filter_map do |phase|
          next if Assistant::Action.exists?(kind: "external_notice", project:, subject: phase)

          open = WorkPackage.where(project:, project_phase_definition_id: phase.definition_id)
                            .where.not(status_id: Assistant::Facts.closed_status_ids).count
          gate = phase.finish_gate_name.presence || phase.name
          external_draft(
            phase, date: phase.finish_date,
                   subject: I18n.t("assistant.duties.release_watch.external.gate_subject", project: project.name, phase: phase.name,
                                                                                           date: l(phase.finish_date)),
                   body: I18n.t("assistant.duties.release_watch.external.gate_body", phase: phase.name, gate:, date: l(phase.finish_date), open:),
                   because: [I18n.t("assistant.duties.release_watch.external.gate_because", phase: phase.name, date: l(phase.finish_date))]
          )
        end.first
      end

      def external_draft(record, date:, subject:, body:, because:)
        action = propose(
          kind: "external_notice", subject: record, auto_execute: false,
          title: I18n.t("assistant.duties.release_watch.external.headline", name: record.try(:name), date: l(date)),
          steps: [{ "op" => "send_mail",
                    "attributes" => { "project_id" => project.id, "to" => outside_addresses, "subject" => subject, "body" => body,
                                      "signed_for" => delegator.name } }]
        )
        return if action.status == "failed"

        offer(action, headline: action.title, because:, subject: record)
      end

      def closed_versions
        versions = scope["version_id"] ? Version.where(id: scope["version_id"]) : project.versions
        versions.where(status: "closed", updated_at: NOTES_LOOKBACK.ago..)
      end

      def can_draft_news?
        Assistant::Llm.configured? && !Assistant::Usage.near_budget?(project:) && project.module_enabled?(:news) &&
          delegator.allowed_in_project?(:manage_news, project)
      end

      # Phases carry no record of their gate being passed; the next phase having
      # started, or the last one's finish date, within the lookback stands for it.
      def passed_phases
        return [] unless delegator.allowed_in_project?(:view_project_phases, project)

        phases = project.phases.active.includes(:definition).to_a.sort_by(&:position)
        phases.each_with_index.filter_map do |phase, index|
          following = phases[index + 1]
          gated = phase.finish_gate? || following&.start_gate?
          passed_on = following ? following.start_date : phase.finish_date
          phase if gated && passed_on && ((today - PHASE_LOOKBACK_DAYS)..today).cover?(passed_on)
        end
      end

      def phase_news(phase)
        return unless can_draft_news?
        return if Assistant::Action.exists?(kind: "phase_news", project:, subject: phase)

        work = WorkPackage.where(project:, project_phase_definition_id: phase.definition_id).includes(:type).order(:type_id, :id)
        closed = Assistant::Facts.closed_status_ids
        material = { "TEMPLATE" => I18n.t("assistant.templates.phase_news"), "phase" => phase.name,
                     "from" => phase.start_date&.iso8601, "to" => phase.finish_date&.iso8601,
                     "gate" => phase.finish_gate? ? phase.finish_gate_name : nil,
                     "next_phase" => project.phases.active.includes(:definition).select { it.position > phase.position }
                                            .min_by(&:position)&.name,
                     "done" => work.where(status_id: closed).limit(80).map do
                       { "id" => it.id, "type" => it.type&.name, "subject" => it.subject }
                     end,
                     "still_open" => work.where.not(status_id: closed).count }
        text = write(PHASE_SYSTEM, material, max_tokens: 2500)
        return if text["title"].blank? || text["description"].blank?

        action = propose(kind: "phase_news", title: I18n.t("assistant.duties.release_watch.phase_headline", phase: phase.name),
                         steps: [{ "op" => "publish_news",
                                   "attributes" => { "project_id" => project.id, "title" => text["title"].to_s.truncate(255),
                                                     "summary" => text["summary"].to_s.truncate(255),
                                                     "description" => text["description"] } }],
                         subject: phase, auto_execute: false)
        offer(action, headline: action.title, because: [text["summary"].to_s], subject: phase)
      rescue Assistant::Llm::Error
        nil
      end

      def release_notes(version)
        return unless can_draft_news?
        return if Assistant::Action.exists?(kind: "release_notes", project:, subject: version)

        done = WorkPackage.with_target_version(version.id).where(status_id: Assistant::Facts.closed_status_ids)
                          .includes(:type).order(:type_id, :id).limit(80)
        material = { "TEMPLATE" => I18n.t("assistant.templates.release_notes"), "version" => version.name,
                     "date" => (version.effective_date || today).iso8601,
                     "description" => Assistant::Text.plain(version.description).truncate(600),
                     "done" => done.map { { "id" => it.id, "type" => it.type&.name, "subject" => it.subject } },
                     "still_open" => WorkPackage.with_target_version(version.id)
                                                .where.not(status_id: Assistant::Facts.closed_status_ids).count }
        text = write(NOTES_SYSTEM, material, max_tokens: 2500)
        return if text["title"].blank? || text["description"].blank?

        action = propose(kind: "release_notes", title: I18n.t("assistant.duties.release_watch.notes_headline", version: version.name),
                         steps: [{ "op" => "publish_news",
                                   "attributes" => { "project_id" => project.id, "title" => text["title"].to_s.truncate(255),
                                                     "summary" => text["summary"].to_s.truncate(255),
                                                     "description" => text["description"] } }],
                         subject: version, auto_execute: false)
        offer(action, headline: action.title, because: [text["summary"].to_s], subject: version)
      rescue Assistant::Llm::Error
        nil
      end
    end
  end
end
