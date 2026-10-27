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
  # The line under the work package's header right after it was put into a
  # version (S4.1.4): that it contradicts what was said about "next release",
  # or that it is dated after the version's release date.
  class VersionMoveAside
    DETECTOR = "version_move_aside"

    class << self
      def after_add(work_package, version_ids, user)
        return unless user.logged? && !user.is_a?(AssistantUser)

        Version.where(id: version_ids).detect { new(work_package:, version: it, user:).call }
      rescue StandardError => e
        Rails.logger.error("[assistant] version move #{work_package&.id}: #{e.class} #{e.message}")
      end
    end

    def initialize(work_package:, version:, user:)
      @work_package = work_package
      @version = version
      @user = user
    end

    def call
      return false unless relevant? && (words = contradiction || late)

      fingerprint = "wp:#{work_package.id}:version:#{version.id}"
      signal = Assistant::Signal.find_by(recipient: user, detector: DETECTOR, fingerprint:) ||
               Assistant::Signal.offer!(detector: DETECTOR, fingerprint:, recipient: user, project:, subject: work_package,
                                        channel: "inline", state: "pending", score: 0, deliver_at: Time.current,
                                        payload: payload(words))
      return false unless signal && signal.outcome.nil?

      signal.update!(payload: signal.payload.merge(payload(words)).merge(
        "aside_until" => Assistant::Proactive::Immediate::ASIDE_FOR.from_now.iso8601
      ))
    end

    private

    attr_reader :work_package, :version, :user

    def project = work_package.project

    def relevant?
      Assistant::Facts.open?(work_package) && Assistant::Surface.available?(project, user) &&
        user.allowed_in_work_package?(:edit_work_packages, work_package)
    end

    def payload(words)
      { "headline" => words.first, "because" => words.drop(1), "nature" => "decision", "certainty" => "fact", "why" => "editing",
        "options" => [], "field" => "version" }
    end

    def contradiction
      item = Assistant::Intent.live.where(project:, kind: "deferral", subject: work_package, due_anchor_type: "Version")
                              .where(stated_at: 60.days.ago..).order(:stated_at).last
      later = item&.due_anchor
      return unless later.is_a?(Version) && later.id != version.id &&
                    (version.effective_date.nil? || later.effective_date.nil? || version.effective_date < later.effective_date)

      [I18n.t("assistant.aside.version_move.deferred", ref: "##{work_package.id}", version: version.name, later: later.name),
       I18n.t("assistant.aside.version_move.said", date: Assistant::Text.day(item.stated_at.to_date),
                                                   quote: item.quote.to_s.truncate(60))]
    end

    def late
      return unless work_package.due_date && version.effective_date && work_package.due_date > version.effective_date

      [I18n.t("assistant.aside.version_move.late", ref: "##{work_package.id}", date: Assistant::Text.day(work_package.due_date),
                                                   version: version.name),
       I18n.t("assistant.aside.version_move.released", version: version.name, release: Assistant::Text.day(version.effective_date))]
    end
  end
end
