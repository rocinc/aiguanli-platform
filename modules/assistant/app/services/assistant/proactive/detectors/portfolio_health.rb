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
      # On a portfolio or program (04 E3): once a week, whoever leads it hears
      # which of its projects say they are better off than their facts, and
      # who is booked past their hours by several of them at once — the
      # cross-project picture no single project's lead sees.
      class PortfolioHealth < Base
        def candidates
          return [] unless project.workspace_type.in?(%w[portfolio program])

          briefs = leads.filter_map do |lead|
            health = Assistant::Facts::PortfolioHealth.new(project, viewer: lead, today:)
            mismatched = health.mismatched
            conflicts = health.conflicts
            next if mismatched.empty? && conflicts.empty?

            build(lead, health, mismatched, conflicts)
          end
          briefs + project_lead_notices
        end

        private

        # 04 E3 主动: someone overbooked across several of these projects is
        # told to the lead of each of those projects too, with the others named.
        def project_lead_notices
          lead = leads.first or return []

          Assistant::Facts::PortfolioHealth.new(project, viewer: lead, today:).conflicts.flat_map do |conflict|
            conflict.projects.flat_map do |member_project|
              Routing.leads(member_project).reject { leads.include?(it) || it == conflict.user }.map do |recipient|
                others = conflict.projects - [member_project]
                Candidate.build(
                  detector: self.class.key, project: member_project,
                  fingerprint: "#{conflict.user.id}:#{member_project.id}:#{today.cwyear}-#{today.cweek}", recipient:,
                  subject: member_project, nature: :team, channel: "brief",
                  headline: t("overbooked_headline", name: conflict.user.name, count: conflict.projects.size),
                  because: [conflict_line(conflict), t("overbooked_others", list: others.map(&:name).join(t("separator")))],
                  impact: { people: 1, cascade: conflict.projects.size },
                  facts: { user_id: conflict.user.id, projects: conflict.projects.map(&:id) }
                )
              end
            end
          end
        end

        def build(lead, health, mismatched, conflicts)
          candidate(
            fingerprint: "#{today.cwyear}-#{today.cweek}", recipient: lead, subject: project, nature: :team, channel: "brief",
            headline: t("headline", count: health.projects.size, mismatched: mismatched.size, conflicts: conflicts.size),
            because: [*mismatched.first(4).map { mismatch_line(it) }, *conflicts.first(3).map { conflict_line(it) }],
            impact: { people: conflicts.size, cascade: mismatched.size },
            facts: { projects: health.projects.map(&:id), mismatched: mismatched.map { it.project.id },
                     conflicts: conflicts.map { it.user.id } }
          )
        end

        def mismatch_line(row)
          t("mismatch", project: row.project.name, set: status(row.status_code), suggested: status(row.suggested),
                        reason: row.reasons.first.to_s.truncate(80))
        end

        def conflict_line(conflict)
          t("conflict", name: conflict.user.name, load: conflict.load, capacity: conflict.capacity,
                        list: conflict.projects.map(&:name).join(t("separator")))
        end

        def status(code) = I18n.t("assistant.duties.weekly_status.codes.#{code}", default: code.to_s)
      end
    end
  end
end
