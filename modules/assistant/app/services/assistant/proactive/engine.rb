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
    # detectors → value gate → options as real actions → timing and channel →
    # words (model, only for what passed) → signal. Delivery sends them.
    class Engine
      def initialize(project, today: Date.current, now: Time.current, detectors: Detectors.all, writer: Writer)
        @project = project
        @today = today
        @now = now
        @detectors = detectors
        @writer = writer
      end

      def sweep
        return [] unless @project.module_enabled?(:assistant)

        Assistant::Membership.ensure_member!(@project)
        since = last_sweep_at
        settings = ProjectSettings.for(@project)
        signals = @detectors.select { settings.enabled?(it.key) }.flat_map do |detector|
          run(detector, since)
        rescue StandardError => e
          Rails.logger.error("[assistant] #{detector.key} on #{@project.identifier}: #{e.class} #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}")
          []
        end
        Assistant::Event.where(project: @project, processed_at: nil).where(created_at: ..@now).update_all(processed_at: @now)
        Feedback.expire_ignored!(@project, now: @now)
        Outdated.retract!(@project)
        Feedback.retune!(@project, since:)
        signals
      end

      # Detectors write their words when they build a candidate, so a detector
      # runs again in each recipient's language and each candidate is taken
      # from the run in the language of the person it is addressed to.
      def run(detector, since = last_sweep_at)
        first = locale_of(nil)
        found = { first => candidates(detector, since, first) }
        found[first].map { locale_of(it.recipient) }.uniq.each { found[it] ||= candidates(detector, since, it) }
        found.flat_map { |lang, list| list.select { locale_of(it.recipient) == lang } }.filter_map do |candidate|
          OpenProject::LocaleHelper.with_locale_for(candidate.recipient) { consider(candidate) }
        end
      end

      def candidates(detector, since, lang)
        I18n.with_locale(lang) { detector.new(@project, today: @today, since:).candidates.uniq(&:key) }
      end

      def consider(candidate)
        verdict = Gate.new(candidate, today: @today).call
        if verdict.interrupt? && demoted.include?(candidate.detector)
          verdict = verdict.with(route: :brief, reasons: verdict.reasons + ["demoted"])
        end
        return nil unless verdict.pass || verdict.pool?
        return nil if verdict.pool? && candidate.certainty != :fact

        options = prepare(candidate)
        channel, deliver_at = place(candidate, verdict)
        verdict = verdict.with(reasons: verdict.reasons + ["over_budget"]) if held_back?(candidate, verdict, channel)
        words = verdict.pool? ? fallback(candidate, options) : @writer.new(candidate, options).call
        public_comment = channel == "comment" ? public_comment_action(candidate) : nil
        channel = "brief" if channel == "comment" && public_comment.nil?
        release_cold_start_pool(candidate)
        create_signal(candidate, verdict, channel, deliver_at, options, words, public_comment)
      end

      private

      def release_cold_start_pool(candidate)
        pool = Assistant::Signal.cold_start_pool.where(recipient: candidate.recipient, detector: candidate.detector.to_s)
        subject = candidate.subject.is_a?(ActiveRecord::Base) ? candidate.subject : nil
        pool = subject ? pool.where(fingerprint: candidate.fingerprint).or(pool.where(subject:)) : pool.where(fingerprint: candidate.fingerprint)
        Assistant::Action.proposed.where(id: pool.select(:action_id)).update_all(status: "superseded")
        pool.destroy_all
      end

      def held_back?(candidate, verdict, channel)
        verdict.interrupt? && channel == "brief" && candidate.channel.in?([nil, "notification"])
      end

      def demoted = @demoted ||= Feedback.demoted_detectors(@project)

      def last_sweep_at
        Assistant::Event.where(project: @project).where.not(processed_at: nil).maximum(:processed_at) || 1.day.ago
      end

      # Every option is an action, previewed as the recipient, waiting for them.
      def prepare(candidate)
        candidate.options_for(candidate.recipient).filter_map do |option|
          steps = Array(option[:steps])
          action = if steps.any?
                     Assistant::Actions::Propose.call(
                       kind: option[:kind].to_s, title: option[:label], steps:, on_behalf_of: candidate.recipient,
                       project: candidate.project, subject: candidate.subject.is_a?(ActiveRecord::Base) ? candidate.subject : nil,
                       basis: basis(candidate), auto_execute: false
                     )
                   end
          next if action&.status == "failed"

          option.merge(action:)
        end
      end

      def basis(candidate)
        subject = candidate.subject
        entries = []
        entries << Assistant::Basis.for(subject, label: candidate.because.first) if subject.respond_to?(:to_gid)
        entries
      end

      def place(candidate, verdict)
        timing = Timing.new(candidate.recipient, now: @now)
        preference = Assistant::Preference.effective(candidate.recipient, candidate.project)
        return ["inline", @now] if candidate.channel == "inline"
        return ["brief", @now] if verdict.pool?
        return ["comment", @now] if verdict.interrupt? && candidate.channel == "comment" && !preference.quiet?
        if verdict.interrupt? && candidate.channel != "brief" && timing.may_interrupt?(preference.cap)
          return ["notification",
                  @now]
        end

        ["brief", timing.working_now? ? @now : timing.next_brief_at]
      end

      # Said in the assistant's own name on the object, for object and team
      # facts only; the gate already decided it is worth it.
      def public_comment_action(candidate)
        text = candidate.facts[:public_comment]
        return nil unless text.present? && candidate.subject.is_a?(WorkPackage) && candidate.nature.in?(%i[object team])

        action = Assistant::Actions::Propose.call(
          kind: "public_notice", title: I18n.t("assistant.proactive.public_comment_title", id: candidate.subject.id),
          steps: [{ "op" => "comment", "type" => "WorkPackage", "id" => candidate.subject.id, "attributes" => { "notes" => text } }],
          on_behalf_of: nil, project: candidate.project, subject: candidate.subject, basis: basis(candidate), auto_execute: false
        )
        action.status == "failed" ? nil : action
      end

      def fallback(candidate, options) = { "headline" => candidate.headline.to_s, "options" => options.map { it[:label] } }

      def create_signal(candidate, verdict, channel, deliver_at, options, words, public_comment)
        labels = words["options"]
        Assistant::Signal.create!(
          detector: candidate.detector, fingerprint: candidate.fingerprint, recipient: candidate.recipient,
          project: candidate.project, subject: candidate.subject.is_a?(ActiveRecord::Base) ? candidate.subject : nil,
          action: options.first&.dig(:action), channel:, state: verdict.pool? ? "held" : "pending",
          score: verdict.score, deliver_at:,
          payload: {
            "headline" => words["headline"].presence || candidate.headline,
            "because" => candidate.because, "basis_links" => candidate.facts[:basis_links],
            "why_me" => I18n.t("assistant.proactive.why.#{candidate.nature}", locale: locale(candidate)),
            "nature" => candidate.nature.to_s, "field" => candidate.facts[:field]&.to_s, "why" => candidate.facts[:why]&.to_s, "certainty" => candidate.certainty.to_s,
            "options" => options.each_with_index.map do |option, i|
              { "label" => labels[i].presence || option[:label], "consequence" => option[:consequence],
                "action_id" => option[:action]&.id, "kind" => option[:kind].to_s, "reply_draft" => option[:reply_draft],
                "url" => option[:url] }.compact
            end,
            "demoted" => (verdict.reasons & %w[demoted over_budget]).first,
            "waiting_id" => candidate.waiting&.id, "public_comment_action_id" => public_comment&.id, "pooled" => verdict.pool?, "gate" => verdict.reasons,
            "facts" => candidate.facts.except(:public_comment, :why, :field, :basis_links).merge(act_by: candidate.act_by).compact.transform_keys(&:to_s)
                                .transform_values { it.respond_to?(:iso8601) ? it.iso8601 : it }
          }
        )
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def locale(candidate) = locale_of(candidate.recipient)

      def locale_of(user)
        lang = user.try(:language).presence || Setting.default_language.presence || I18n.default_locale
        I18n.available_locales.include?(lang.to_sym) ? lang.to_sym : I18n.default_locale
      end
    end
  end
end
