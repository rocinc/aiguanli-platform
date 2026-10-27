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
  class DateAsideComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    def initialize(aside:)
      super()
      @aside = aside
    end

    attr_reader :aside

    def render? = aside.present?

    def named_shifts = aside.shifts.first(DateAside::MAX_NAMED)

    def more = aside.shifts.size - named_shifts.size

    def shift_line
      return if aside.shifts.empty?

      days = aside.shifts.map(&:days).uniq
      t("assistant.date_aside.shifts.#{shift_direction(days)}", list: shift_list, count: days.first.abs)
    end

    def shift_list
      list = named_shifts.map { "##{it.id}" }.join(t("assistant.card.separator"))
      more.positive? ? t("assistant.date_aside.and_more", list:, count: more) : list
    end

    def shift_direction(days)
      return "moved" unless days.one?

      days.first.positive? ? "later" : "earlier"
    end

    def slip_line(slip)
      key = slip.late ? "late" : "slips"
      t("assistant.date_aside.version.#{key}", version: slip.name, date: Assistant::Text.day(slip.finish),
                                               target: slip.target ? Assistant::Text.day(slip.target) : "")
    end

    def warning_lines = overlap_lines + aside.slips.select(&:late).map { slip_line(it) }

    def quiet_slip_lines = aside.slips.reject(&:late).map { slip_line(it) }

    def announcement = [shift_line, *warning_lines, *quiet_slip_lines].compact.join(" ")

    def overlap_lines
      aside.overlaps.first(DateAside::MAX_NAMED).map do |overlap|
        t("assistant.date_aside.overlap", ref: "##{overlap.id}", subject: overlap.subject.truncate(30),
                                          date: Assistant::Text.day(overlap.start))
      end
    end

    def shift_titles = named_shifts.map { "##{it.id} #{it.subject}" }.join("\n")

    def name = AssistantUser.instance.name
  end
end
