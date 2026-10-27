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
  module Proactive
    module Detectors
      # T-14, T-7 and T-2 working days before a version date: its readiness,
      # to whoever leads it. Only said when something is actually open, late,
      # unassigned or unscheduled; a clean version gets one line in the brief.
      class VersionCheckpoint < Base
        CHECKPOINTS = [14, 7, 2].freeze

        def candidates
          project.shared_versions.where(status: "open").where.not(effective_date: nil).flat_map do |version|
            left = Assistant::Facts.working_days_between(today + 1, version.effective_date)
            checkpoint = CHECKPOINTS.find { it == left }
            next [] unless checkpoint

            readiness = Assistant::Facts::VersionReadiness.new(version, today:)
            next [] if readiness.work_packages.empty?

            leads.map { build(version, readiness, checkpoint, it) }
          end
        end

        def options(version, readiness)
          list = []
          if readiness.slip_days.positive?
            date = Assistant::Facts.add_working_days(version.effective_date, readiness.slip_days)
            list << option(t("move", date: day(date)), t("move_consequence"), "move_version",
                           [{ "op" => "update_version", "type" => "Version", "id" => version.id,
                              "attributes" => { "effective_date" => date.iso8601 } }])
          end
          later = readiness.open.reject(&:due_date).presence || readiness.overdue
          next_version = project.shared_versions.where(status: "open").where("effective_date > ?", version.effective_date)
                                .order(:effective_date).first
          if later.any? && next_version
            list << option(t("defer", count: later.size, version: next_version.name), t("defer_consequence"), "defer_scope",
                           later.first(5).map { step(it, { "version_id" => next_version.id }) })
          end
          list
        end

        private

        def build(version, readiness, checkpoint, lead)
          forecast = readiness.forecast_finish
          late_pace = forecast && forecast > version.effective_date
          problems = readiness.overdue.size + readiness.unassigned.size + readiness.unscheduled.size + readiness.slip_days +
                     readiness.blocked.size + (late_pace ? 1 : 0)
          candidate(
            fingerprint: "#{version.id}:T-#{checkpoint}", recipient: lead, subject: version, nature: :team,
            channel: problems.zero? ? "brief" : nil,
            headline: t(problems.zero? ? "clean" : "headline", version: version.name, days: checkpoint,
                                                               done: readiness.done_ratio, open: readiness.open.size),
            because: [readiness.because,
                      (t("overdue", list: readiness.overdue.first(5).map { "##{it.id}" }.join("、")) if readiness.overdue.any?),
                      (t("unassigned", count: readiness.unassigned.size) if readiness.unassigned.any?),
                      (t("unscheduled", count: readiness.unscheduled.size) if readiness.unscheduled.any?),
                      (t("slip", days: readiness.slip_days) if readiness.slip_days.positive?),
                      (t("blocked", list: readiness.blocked.first(5).map { "##{it.id}" }.join("、")) if readiness.blocked.any?),
                      (t("defects", count: readiness.open_defects.size) if readiness.open_defects.any?),
                      (t("pace", date: day(forecast)) if late_pace)].compact,
            impact: { critical_path: readiness.slip_days.positive? || late_pace, external: version.sharing != "none",
                      people: readiness.open.filter_map(&:assigned_to_id).uniq.size, cascade: problems.positive? },
            act_by: version.effective_date, effort_days: 1,
            steps_for: ->(_user) { options(version, readiness) }
          )
        end
      end
    end
  end
end
