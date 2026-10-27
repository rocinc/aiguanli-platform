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
  # The line beside a date while someone is changing it (03 §3.5 渠道 2):
  # "this moves #73 and #75 by 5 days, v2.0 slips to 10/9". The change is
  # run through Preview, so the platform's own scheduling says what follows; the
  # result is kept per work package state and dates, since the dialog asks
  # again on every keystroke.
  class DateAside
    DETECTOR = "date_aside"
    MAX_NAMED = 4

    Shift = Data.define(:id, :subject, :days)
    Slip = Data.define(:name, :finish, :target, :late)
    # A successor scheduled by hand does not move with it; it would start
    # before this is done.
    Overlap = Data.define(:id, :subject, :start)

    Result = Data.define(:shifts, :slips, :overlaps) do
      def any? = shifts.any? || slips.any? || overlaps.any?
    end

    def self.for(work_package, user) = new(work_package, user).call

    def self.fingerprint(work_package)
      "#{work_package.id}:#{work_package.start_date&.iso8601}:#{work_package.due_date&.iso8601}"
    end

    def initialize(work_package, user)
      @work_package = work_package
      @user = user
    end

    attr_reader :work_package, :user

    def call
      return unless relevant?

      result = Rails.cache.fetch(cache_key, expires_in: 10.minutes) { compute }&.then { it.any? ? it : nil }
      mark_shown if result
      result
    end

    private

    # What the sweep checks before telling this person the same consequence again after the save.
    def mark_shown
      attributes = { recipient: user, detector: DETECTOR, fingerprint: self.class.fingerprint(work_package) }
      return if Assistant::Signal.exists?(**attributes)

      Assistant::Signal.create!(**attributes, project: work_package.project, subject: work_package, channel: "inline",
                                              state: "expired", deliver_at: Time.current)
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    def relevant?
      work_package.persisted? && (work_package.start_date_changed? || work_package.due_date_changed?) &&
        Assistant::Surface.available?(work_package.project, user) &&
        !Assistant::Preference.effective(user, work_package.project).muted?(DETECTOR)
    end

    def cache_key
      ["assistant/date_aside", work_package.id, work_package.lock_version, work_package.start_date,
       work_package.due_date, user.id]
    end

    def compute
      preview = Assistant::Actions::Preview.new(steps: [step], user:).call
      return Result.new(shifts: [], slips: [], overlaps: []) unless preview&.success

      moved = preview.changes.map { it["id"] if it["type"] == "WorkPackage" }
      Result.new(shifts: shifts(preview), slips: slips(preview), overlaps: overlaps(moved))
    end

    def step
      { "op" => "update_work_package", "type" => "WorkPackage", "id" => work_package.id,
        "attributes" => { "start_date" => work_package.start_date&.iso8601,
                          "due_date" => work_package.due_date&.iso8601 } }
    end

    def shifts(preview)
      preview.changes.filter_map do |change|
        next if change["type"] != "WorkPackage" || change["id"] == work_package.id || change["created"]

        was, now = Array(change.dig("changes", "due_date") || change.dig("changes", "start_date"))
        next unless was && now

        days = working_days_moved(Date.parse(was), Date.parse(now))
        Shift.new(id: change["id"], subject: change["label"].to_s.sub(/\A#\d+ /, ""), days:) unless days.zero?
      end
    end

    def working_days_moved(was, now)
      return Assistant::Facts.working_days_between(was + 1, now) if now >= was

      -Assistant::Facts.working_days_between(now + 1, was)
    end

    def overlaps(moved)
      return [] unless work_package.due_date

      successors = Relation.follows.where(to_id: work_package.id).where.not(from_id: moved).select(:from_id)
      WorkPackage.visible(user).where(id: successors, schedule_manually: true)
                 .where(start_date: ..work_package.due_date).order(:start_date)
                 .map { Overlap.new(id: it.id, subject: it.subject, start: it.start_date) }
    end

    def slips(preview)
      preview.version_slips.filter_map do |slip|
        next unless slip["finish_after"] && slip["finish_before"] && slip["finish_after"] > slip["finish_before"]

        Slip.new(name: slip["name"], finish: Date.parse(slip["finish_after"]),
                 target: slip["target"] && Date.parse(slip["target"]), late: slip["late"])
      end
    end
  end
end
