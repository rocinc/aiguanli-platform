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

module Assistant
  module Proactive
    module Detectors
      # A kind of work that keeps taking far longer than planned (04 A2:
      # "某类任务实际工期平均是计划的 1.6 倍"), said where it can still change a
      # plan: in the brief of whoever leads, in the days before a sprint
      # starts, with the open work of that type in it and the factor to apply.
      class SystematicUnderestimate < Base
        LEAD_WORKING_DAYS = 3
        RATIO_PERCENT = 150

        def candidates
          sprint = upcoming_sprint or return []
          bias = Assistant::Facts::EstimateBias.new(project, today:)
          threshold = RATIO_PERCENT.fdiv(100)
          bias.rows.select { worst(it) && worst(it) >= threshold }.flat_map do |row|
            planned = sprint.work_packages.where(type: row.type).where.not(status_id: Assistant::Facts.closed_status_ids).to_a
            next [] if planned.empty?

            leads.map { build(sprint, row, planned, it) }
          end
        end

        private

        def upcoming_sprint
          return unless defined?(::Sprint)

          ::Sprint.where(project:).where(start_date: today..).order(:start_date).detect do |sprint|
            Assistant::Facts.working_days_between(today + 1, sprint.start_date - 1) < LEAD_WORKING_DAYS
          end
        end

        def worst(row) = [row.duration_ratio, row.hours_ratio].compact.max

        def build(sprint, row, planned, lead)
          factor = worst(row)
          candidate(
            fingerprint: "#{sprint.id}:#{row.type.id}", recipient: lead, subject: project, nature: :team, channel: "brief",
            headline: t("headline", type: row.type.name, factor:),
            because: [(t("duration", ratio: row.duration_ratio, count: row.samples) if row.duration_ratio),
                      (t("hours", ratio: row.hours_ratio, count: row.samples) if row.hours_ratio),
                      t("examples", list: row.examples.map { "##{it}" }.join(t("separator"))),
                      t("planned", sprint: sprint.name, list: planned.first(5).map { "##{it.id}" }.join(t("separator")))].compact,
            impact: { cascade: planned.size, people: planned.filter_map(&:assigned_to_id).uniq.size },
            act_by: sprint.start_date, facts: { type: row.type.name, duration_ratio: row.duration_ratio,
                                                hours_ratio: row.hours_ratio, samples: row.samples, sprint_id: sprint.id },
            steps_for: ->(_user) { options(planned, factor) }
          )
        end

        def options(planned, factor)
          estimated = planned.select { it.estimated_hours.to_f.positive? }
          return [] if estimated.empty?

          [option(t("scale", factor:, count: estimated.size), t("scale_consequence"), "scale_estimates",
                  estimated.map { step(it, { "estimated_hours" => (it.estimated_hours * factor).round(1) }) })]
        end
      end
    end
  end
end
