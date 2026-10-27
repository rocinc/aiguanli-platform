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
  # How a dimension of a profile reads, the same on the team table and on
  # the member's own page.
  module AppraisalFormatting
    def dimension_label(key) = I18n.t("assistant.appraisals.dimensions.#{key}")

    def dimension_value(dim)
      return I18n.t("assistant.performance.insufficient") if dim["insufficient"]
      return "–" if dim["value"].nil?

      format_number(dim["value"], dim["unit"])
    end

    def format_number(value, unit)
      number = value.is_a?(Float) ? helpers.number_with_precision(value, precision: 2, strip_insignificant_zeros: true) : value
      case unit
      when "%" then "#{number}%"
      when "×" then "#{number}×"
      when "/40h" then I18n.t("assistant.performance.per_week", value: number)
      else number.to_s
      end
    end

    def median_text(dim)
      median = dim["team_median"]
      median.nil? ? nil : I18n.t("assistant.performance.team_median", value: format_number(median, dim["unit"]))
    end

    def trend_line(dim, period)
      previous = dim["previous"]
      return nil if previous.nil? || dim["insufficient"]

      I18n.t("assistant.performance.trend", days: period, value: format_number(previous, dim["unit"]))
    end

    def views_line(views)
      days = Assistant::AppraisalView::WINDOW_DAYS
      return I18n.t("assistant.performance.no_views", days:) if views.empty?

      latest = views.first
      I18n.t("assistant.performance.views_summary", days:, count: views.map(&:viewer_id).uniq.size, name: latest.viewer.name,
                                                    date: Assistant::Text.day(latest.created_at))
    end

    def period_label(key) = I18n.t("assistant.performance.periods.p#{key}")
  end
end
