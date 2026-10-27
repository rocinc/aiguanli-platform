# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  module Proactive
    # The decision-moment detectors, run once more right after the save that
    # made them true, as the person who saved (S4). The sweep finds the same
    # signal later and drops it: the fingerprint is already taken.
    class Immediate
      ASIDE_FOR = 10.minutes
      ASIDE_UNTIL = "(assistant_signals.payload ->> 'aside_until')::timestamptz"

      Plain = Data.define(:candidate, :options) do
        def call = { "headline" => candidate.headline.to_s, "options" => options.map { it[:label] } }
      end

      class << self
        def fresh_sql = Arel.sql(ActiveRecord::Base.sanitize_sql_array(["#{ASIDE_UNTIL} > ?", Time.current]))

        def not_fresh_sql
          Arel.sql(ActiveRecord::Base.sanitize_sql_array(["#{ASIDE_UNTIL} IS NULL OR #{ASIDE_UNTIL} <= ?", Time.current]))
        end

        def subscribe!
          OpenProject::Notifications.subscribe(OpenProject::Events::JOURNAL_CREATED) do |payload|
            journal = payload[:journal]
            next unless journal.is_a?(Journal) && journal.journable_type == "WorkPackage"

            ActiveRecord.after_all_transactions_commit { after_save(journal) }
          end
        end

        def after_save(journal)
          event = Assistant::Event.by_humans.find_by(journal_id: journal.id)
          detector = event && detector_for(event)
          return unless detector

          project = event.project
          actor = event.actor
          return unless project&.module_enabled?(:assistant) && Assistant::Surface.available?(project, actor)

          offer_aside(run(detector, project, actor, since: event.created_at))
        rescue StandardError => e
          Rails.logger.error("[assistant] immediate #{journal&.id}: #{e.class} #{e.message}")
        end

        # Someone was asked for something in a comment (S4.1.10): what saying yes costs them is told under that
        # comment as soon as the request has been read.
        def weigh_requests(items)
          asked = Array(items).select { it.kind == "commitment" && it.strength == "requested" && it.owner.is_a?(User) }
          asked.group_by(&:owner).each do |owner, list|
            project = list.first.project
            next unless project.module_enabled?(:assistant) && Assistant::Surface.available?(project, owner)

            signals = run(Detectors::RequestWeigh, project, owner, since: list.map(&:stated_at).min)
            signals.each { |signal| bind_to_comment(signal, list) }
          end
        rescue StandardError => e
          Rails.logger.error("[assistant] immediate requests: #{e.class} #{e.message}")
        end

        def run(detector, project, actor, since:, today: Date.current)
          engine = Engine.new(project, today:, detectors: [detector], writer: Plain)
          found = OpenProject::LocaleHelper.with_locale_for(actor) do
            detector.new(project, today:, since:).candidates.uniq(&:key).select { it.recipient == actor }
          end
          found.filter_map { |candidate| OpenProject::LocaleHelper.with_locale_for(actor) { engine.consider(candidate) } }
        end

        def fresh_for(work_package, user, only: nil, except: nil)
          scope = Assistant::Signal.live.where(channel: "inline", recipient: user, subject: work_package, state: "pending")
                                   .where(fresh_sql).order(score: :desc, created_at: :desc)
          scope = scope.where("assistant_signals.payload ->> 'field' IN (?)", Array(only)) if only
          scope = scope.where("assistant_signals.payload ->> 'field' IS NULL OR assistant_signals.payload ->> 'field' NOT IN (?)", Array(except)) if except.present?
          scope.first
        end

        private

        def detector_for(event)
          return Detectors::PossibleDuplicate if event.kind == "work_package.created"
          return unless event.kind == "work_package.updated"

          if event.changed?("assigned_to_id") then Detectors::AssigneeChangeLoad
          elsif event.changed?("status_id") then Detectors::CloseWithOpenChildren
          elsif event.changed?("estimated_hours") || event.changed?("remaining_hours") then Detectors::EstimateChangeEffect
          end
        end

        def bind_to_comment(signal, requests)
          source = requests.find { "intent:#{it.id}" == signal.fingerprint }&.source
          return unless source.respond_to?(:to_gid)

          signal.update!(payload: signal.payload.merge("source_gid" => source.to_gid.to_s))
        end

        def offer_aside(signals)
          best = signals.select { it.state == "pending" }.max_by(&:score)
          best&.update!(payload: best.payload.merge("aside_until" => ASIDE_FOR.from_now.iso8601))
        end
      end
    end
  end
end
