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
  # The line on the backlogs page after someone drags a work package into a
  # sprint (S4.1.3): the sprint's room before and after, and what no longer
  # fits. One notice per person and sprint, rewritten on each drag.
  class SprintMoveAside
    DETECTOR = "sprint_move_aside"
    MAX_BASIS = 5

    def self.for(...) = new(...).call

    def initialize(work_package:, user:)
      @work_package = work_package
      @user = user
      @sprint = work_package.try(:sprint)
    end

    def call
      return unless relevant? && free_after.negative?

      signal = Assistant::Signal.find_by(recipient: user, detector: DETECTOR, fingerprint:)
      return signal if signal&.outcome.present?

      signal ? refresh(signal) : offer
    end

    private

    attr_reader :work_package, :user, :sprint

    def project = work_package.project

    def relevant?
      sprint && Assistant::Facts.open?(work_package) && Assistant::Surface.available?(project, user) &&
        user.allowed_in_project?(:edit_work_packages, project)
    end

    def fingerprint = "sprint:#{sprint.id}"

    def facts = @facts ||= Assistant::Facts::SprintFacts.new(sprint)

    def hours_of(wp) = (wp.remaining_hours || wp.estimated_hours).to_f

    def free_after = @free_after ||= (facts.capacity_hours - facts.remaining_hours).round(1)

    def free_before = (free_after + hours_of(work_package)).round(1)

    def squeezed
      @squeezed ||= begin
        room = facts.capacity_hours
        sprint.work_packages.order_by_position.includes(:status).select { Assistant::Facts.open?(it) }.select do |wp|
          room -= hours_of(wp)
          room.negative?
        end
      end
    end

    def payload
      { "headline" => headline, "because" => squeezed.first(MAX_BASIS).map { because(it) }, "nature" => "decision",
        "certainty" => "fact", "why" => "editing", "options" => [] }
    end

    def headline
      I18n.t("assistant.aside.sprint_move", sprint: sprint.name.truncate(10), before: signed(free_before),
                                            after: signed(free_after), what: squeezed_names)
    end

    def squeezed_names
      first = "##{squeezed.first.id}"
      squeezed.size > 1 ? I18n.t("assistant.aside.sprint_move_more", list: first, count: squeezed.size) : first
    end

    def signed(hours) = hours.negative? ? "−#{hours.abs.round}" : hours.round.to_s

    def because(wp)
      I18n.t("assistant.aside.sprint_move_item", ref: "##{wp.id}", subject: wp.subject.truncate(40), hours: hours_of(wp).round(1))
    end

    def offer
      Assistant::Signal.offer!(detector: DETECTOR, fingerprint:, recipient: user, project:, channel: "inline", state: "pending",
                               score: 0, deliver_at: Time.current, payload:)
    end

    def refresh(signal)
      signal.update!(payload: signal.payload.merge(payload))
      signal
    end
  end
end
