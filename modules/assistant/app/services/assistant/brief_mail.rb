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
  # The brief by email for people who asked for it: once a day, at their brief
  # time on a working day, and only when there is something in it.
  class BriefMail
    LATE = 3.hours

    def initialize(now: Time.current)
      @now = now
    end

    def call
      Assistant::Preference.where(owner_type: User.polymorphic_name, brief_email: true).includes(:owner).find_each { deliver(it) }
    end

    private

    def deliver(preference)
      user = preference.owner
      return unless user.is_a?(User) && user.active? && user.mail.present?

      timing = Assistant::Proactive::Timing.new(user, now: @now)
      return unless due?(preference, timing)

      preference.update_columns(brief_mailed_on: timing.brief_today.to_date)
      User.execute_as(user) do
        brief = Assistant::Brief.new(user:, now: @now)
        Assistant::BriefMailer.daily(user, brief).deliver_now unless brief.empty? && brief.away.nil?
      end
    end

    def due?(preference, timing)
      from = timing.brief_today
      @now.between?(from, from + LATE) && preference.brief_mailed_on != from.to_date &&
        timing.working_day?(from.to_date) && !timing.paused?(from.to_date)
    end
  end
end
