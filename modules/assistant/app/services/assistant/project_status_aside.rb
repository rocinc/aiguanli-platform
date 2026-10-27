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
  # The line beside the project status button right after someone sets it
  # (S4.1.8): what the facts suggest instead, and why, when they are worse.
  class ProjectStatusAside
    DETECTOR = "project_status_aside"

    class << self
      def record(project:, user:)
        expire(project, user)
        return unless user.logged? && Assistant::Surface.available?(project, user)
        return unless user.allowed_in_project?(:edit_project, project)

        row = Assistant::Facts::PortfolioHealth.new(project, viewer: user).row_for(project)
        return unless row.status_code.present? && rank(row.suggested) > rank(row.status_code)

        offer(project, user, row)
      end

      def fresh_for(project:, user:)
        return unless user.logged?

        Assistant::Signal.live.where(detector: DETECTOR, recipient: user, project:, channel: "inline")
                         .where(Assistant::Proactive::Immediate.fresh_sql).order(:id).last
      end

      private

      def rank(code) = %w[on_track at_risk off_track].index(code.to_s) || -1

      def expire(project, user)
        fresh = Assistant::Signal.live.where(detector: DETECTOR, recipient: user, project:).where(Assistant::Proactive::Immediate.fresh_sql)
        fresh.find_each { it.update!(payload: it.payload.merge("aside_until" => Time.current.iso8601)) }
      end

      def offer(project, user, row)
        fingerprint = "status:#{project.id}:#{row.status_code}:#{row.suggested}"
        signal = Assistant::Signal.find_by(recipient: user, detector: DETECTOR, fingerprint:)
        signal ||= Assistant::Signal.offer!(detector: DETECTOR, fingerprint:, recipient: user, project:, channel: "inline",
                                            state: "pending", score: 0, deliver_at: Time.current, payload: payload(row))
        return unless signal && signal.outcome.nil?

        signal.update!(payload: signal.payload.merge("aside_until" => Assistant::Proactive::Immediate::ASIDE_FOR.from_now.iso8601))
        signal
      end

      def payload(row)
        { "headline" => I18n.t("assistant.aside.project_status", set: name(row.status_code), suggested: name(row.suggested)),
          "because" => row.reasons, "nature" => "decision", "certainty" => "fact", "why" => "editing", "options" => [] }
      end

      def name(code) = I18n.t(code, scope: "js.grid.widgets.project_status")
    end
  end
end
