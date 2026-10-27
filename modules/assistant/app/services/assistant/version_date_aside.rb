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
  # The line beside a version's date while someone edits it (S4.1.7): the
  # open work packages dated later than the new date that fit before. Kept per
  # person and date so "not now" and "stop telling me" are remembered.
  class VersionDateAside
    DETECTOR = "version_date_aside"
    MAX_NAMED = 2
    MAX_BASIS = 5

    def self.for(...) = new(...).call

    def initialize(version:, user:, effective_date:)
      @version = version
      @user = user
      @date = parse(effective_date)
    end

    def call
      return unless relevant?

      outcast = no_longer_fitting
      return if outcast.empty?

      signal = Assistant::Signal.find_by(recipient: user, detector: DETECTOR, fingerprint:) || offer(outcast)
      signal if signal&.outcome.nil?
    end

    private

    attr_reader :version, :user, :date

    def parse(value)
      Date.iso8601(value.to_s) if value.present?
    rescue Date::Error
      nil
    end

    def project = version.project

    def relevant?
      date && date != version.effective_date && Assistant::Surface.available?(project, user) &&
        user.allowed_in_project?(:manage_versions, project)
    end

    def fingerprint = "version:#{version.id}:#{date.iso8601}"

    def no_longer_fitting
      visible = WorkPackage.visible(user)
      Assistant::Facts::VersionReadiness.new(version).open.select do |wp|
        wp.due_date && wp.due_date > date && (version.effective_date.nil? || wp.due_date <= version.effective_date) &&
          visible.exists?(wp.id)
      end.sort_by(&:due_date)
    end

    def offer(outcast)
      Assistant::Signal.offer!(
        detector: DETECTOR, fingerprint:, recipient: user, project:, channel: "inline", state: "pending", score: 0,
        deliver_at: Time.current,
        payload: { "headline" => headline(outcast), "because" => outcast.first(MAX_BASIS).map { because(it) },
                   "nature" => "decision", "certainty" => "fact", "why" => "editing", "options" => [] }
      )
    end

    def headline(outcast)
      named = outcast.first(MAX_NAMED).map { "##{it.id}" }.join(I18n.t("assistant.card.separator"))
      I18n.t("assistant.aside.version_date", count: outcast.size, date: Assistant::Text.day(date), list: named,
                                             finish: Assistant::Text.day(outcast.last.due_date))
    end

    def because(work_package)
      I18n.t("assistant.aside.version_date_item", ref: "##{work_package.id}", subject: work_package.subject.truncate(40),
                                                  date: Assistant::Text.day(work_package.due_date),
                                                  name: work_package.assigned_to&.name || I18n.t("assistant.aside.nobody"))
    end
  end
end
