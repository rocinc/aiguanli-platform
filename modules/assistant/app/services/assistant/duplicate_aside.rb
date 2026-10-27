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
  # The line under the title of a work package that is being written
  # (S4.1.6): the one or two existing ones it may repeat. Nothing is saved
  # for the work package itself; the notice is kept per person and existing
  # work package so "not now" and "stop telling me" are remembered.
  class DuplicateAside
    DETECTOR = "possible_duplicate"
    MIN_LENGTH = 6
    MAX_NAMED = 2

    def self.for(...) = new(...).call

    def initialize(project:, user:, subject:, type_id:)
      @project = project
      @user = user
      @subject = subject.to_s.strip
      @type_id = type_id
    end

    def call
      return unless relevant?

      matches = similar
      return if matches.empty?

      signal = existing(matches.first.first) || offer(matches)
      signal if signal&.outcome.nil?
    end

    private

    attr_reader :project, :user, :subject, :type_id

    def relevant?
      subject.length >= MIN_LENGTH && type_id.present? && Assistant::Surface.available?(project, user) &&
        user.allowed_in_project?(:add_work_packages, project)
    end

    def similar
      found = Assistant::Facts::SimilarSubjects.find(project:, type_id:, subject:)
      visible = WorkPackage.visible(user).where(id: found.map { it.first.id }).pluck(:id)
      found.select { |other, _| visible.include?(other.id) }.first(MAX_NAMED)
    end

    def fingerprint(other) = "draft:#{other.id}"

    def existing(other)
      Assistant::Signal.find_by(recipient: user, detector: DETECTOR, fingerprint: fingerprint(other))
    end

    def offer(matches)
      other, share = matches.first
      Assistant::Signal.offer!(
        detector: DETECTOR, fingerprint: fingerprint(other), recipient: user, project:, channel: "inline", state: "pending",
        score: 0, deliver_at: Time.current,
        payload: { "headline" => headline(matches), "because" => because(other, share), "nature" => "own", "certainty" => "fact",
                   "why_me" => I18n.t("assistant.proactive.why.own"), "options" => [] }
      )
    end

    def headline(matches)
      if matches.one?
        other = matches.first.first
        who = owner_words(other)
        I18n.t("assistant.aside.duplicate.one", ref: "##{other.id}", subject: other.subject.truncate(14), who:)
      else
        I18n.t("assistant.aside.duplicate.many", list: matches.map { "##{it.first.id}" }.join(I18n.t("assistant.card.separator")))
      end
    end

    def owner_words(other)
      return I18n.t("assistant.aside.duplicate.nobody") unless other.assigned_to

      I18n.t("assistant.aside.duplicate.owner", name: other.assigned_to.name)
    end

    def because(other, share)
      [copy(:other, ref: "##{other.id}", subject: other.subject.truncate(60), status: other.status.name,
                    name: other.assigned_to&.name || copy(:nobody)),
       copy(:share, percent: (share * 100).round)]
    end

    def copy(key, **) = I18n.t("assistant.proactive.possible_duplicate.#{key}", **)
  end
end
