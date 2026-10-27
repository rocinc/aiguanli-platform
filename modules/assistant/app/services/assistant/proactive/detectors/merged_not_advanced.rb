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
      # A pull request linked to a work package was merged and the work
      # package still shows an earlier status. With the advance_merged_pr duty
      # the duty moves it; without, the owner is offered the move, and the
      # fact is said on the work package (03 §3.5 channel 6).
      class MergedNotAdvanced < Base
        def candidates
          return [] unless defined?(::GithubPullRequest)

          merged.flat_map do |pr, wps|
            wps.filter_map do |wp|
              target = Assistant::Duties::AdvanceMergedPr.next_status(wp)
              next unless target && wp.assigned_to.is_a?(User)
              next if duty_active?

              build(pr, wp, target)
            end
          end
        end

        private

        def duty_active? = Assistant::Duty.active.exists?(project:, kind: "advance_merged_pr")

        def merged
          ::GithubPullRequest.where(merged: true).where(merged_at: 14.days.ago..)
                             .where(id: ::GithubPullRequest.joins(:work_packages).where(work_packages: { project_id: project.id }).select(:id))
                             .map { [it, it.work_packages.where(project:).where.not(status_id: Assistant::Facts.closed_status_ids).to_a] }
        end

        def build(pr, wp, target)
          candidate(
            fingerprint: "#{wp.id}:pr#{pr.id}", recipient: wp.assigned_to, subject: wp, nature: :object,
            channel: "comment",
            headline: t("headline", number: pr.number, ref: "##{wp.id}", status: wp.status.name),
            because: [t("merged", number: pr.number, title: pr.title.to_s.truncate(60), date: day(pr.merged_at.to_date)),
                      t("status", status: wp.status.name)],
            impact: { cascade: graph.downstream(wp.id).size, critical_path: graph.slack(wp.id)&.<=(1) || false, people: 1 },
            facts: { since: pr.merged_at,
                     public_comment: t("comment", number: pr.number, date: day(pr.merged_at.to_date), status: wp.status.name,
                                                  target: target.name) },
            steps_for: ->(_user) {
              [option(t("advance", status: target.name), t("advance_consequence"), "advance_merged_pr", [step(wp, { "status_id" => target.id })])]
            }
          )
        end
      end
    end
  end
end
