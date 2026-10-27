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
      # The project says "on track" while a version it delivers would finish
      # after its date (03 §3.1, 06 S6). Told to whoever leads, with the status
      # changed to "at risk" and the reason written out, ready to apply.
      class GreenButSlipping < Base
        def candidates
          return [] unless project.status_code.to_s == "on_track"

          slipping = versions.map { Assistant::Facts::VersionReadiness.new(it, today:) }.select { it.slip_days.positive? }
          return [] if slipping.empty?

          worst = slipping.max_by(&:slip_days)
          leads.map { build(worst, slipping, it) }
        end

        private

        def versions
          project.shared_versions.where(status: "open").where.not(effective_date: nil).where(effective_date: today..)
        end

        def build(worst, slipping, lead)
          version = worst.version
          explanation = t("explanation", version: version.name, days: worst.slip_days, finish: day(worst.planned_finish),
                                         date: day(version.effective_date))
          candidate(
            fingerprint: "#{version.id}:#{worst.slip_days}", recipient: lead, subject: project, nature: :team,
            headline: t("headline", version: version.name, days: worst.slip_days),
            because: [t("status"), *slipping.map(&:because)],
            impact: { external: version.sharing != "none", deadline: true,
                      people: worst.open.filter_map(&:assigned_to_id).uniq.size },
            act_by: version.effective_date, effort_days: 1,
            facts: { version_id: version.id, slip_working_days: worst.slip_days, status_code: project.status_code },
            steps_for: lambda do |_user|
              [option(t("mark"), t("mark_consequence"), "mark_at_risk",
                      [{ "op" => "update_project_status", "type" => "Project", "id" => project.id,
                         "attributes" => { "status_code" => "at_risk", "status_explanation" => explanation } }])]
            end
          )
        end
      end
    end
  end
end
