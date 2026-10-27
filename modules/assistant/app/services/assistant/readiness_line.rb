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
  # What a version page says about its own readiness, when there is anything
  # to say: one sentence on the most pressing thing, the rest as details.
  class ReadinessLine
    def initialize(version)
      @version = version
      @readiness = Assistant::Facts::VersionReadiness.new(version)
    end

    attr_reader :readiness

    def sentence
      return if readiness.work_packages.empty?

      @sentence ||= slip || blocked || defects || overdue
    end

    def details
      return [] unless sentence

      [scope, *counts, forecast, effective].compact
    end

    private

    def name = @version.name

    def slip
      return unless readiness.slip_days.positive?

      t("slip", finish: day(readiness.planned_finish), date: day(@version.effective_date), days: readiness.slip_days)
    end

    def blocked = counted("blocked", readiness.blocked.size)

    def defects = counted("defects", readiness.open_defects.size)

    def overdue
      return if readiness.overdue.empty?

      t("overdue", count: readiness.overdue.size)
    end

    def counted(key, count)
      t(key, count:, percent: readiness.done_ratio) if count.positive?
    end

    def scope
      closed = readiness.work_packages.size - readiness.open.size
      t("detail.scope", percent: readiness.done_ratio, closed:, total: readiness.work_packages.size)
    end

    def counts
      { blocked: readiness.blocked, defects: readiness.open_defects, overdue: readiness.overdue }
        .map { |key, list| count(key, list.size) }
    end

    def count(key, count) = (t("detail.#{key}", count:) if count.positive?)

    def forecast
      finish = readiness.open.any? && readiness.forecast_finish
      t("detail.forecast", finish: day(finish)) if finish
    end

    def effective = (t("detail.effective", date: day(@version.effective_date)) if @version.effective_date)

    def day(date) = Assistant::Text.day(date)

    def t(key, **) = I18n.t("assistant.object_line.readiness.#{key}", name:, **)
  end
end
