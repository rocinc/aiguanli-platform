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
      # A pull or merge request has been open, not a draft, for more than two
      # working days without a merge (03 §3.1, 04 E1). The host keeps no
      # reviewer, so the reminder goes to whoever answers for the linked work
      # package (its accountable, else a lead), never to its author.
      class ReviewWaiting < Base
        WORKING_DAYS = 2

        def candidates
          requests.flat_map do |request, wps|
            waited = Assistant::Facts.working_days_between(request.created_at.to_date + 1, today)
            next [] if waited <= WORKING_DAYS

            wps.group_by { reviewer_for(it) }.filter_map do |reviewer, packages|
              build(request, packages, reviewer, waited) if reviewer
            end
          end
        end

        private

        def requests
          [github, gitlab].flatten(1).filter_map do |request|
            wps = request.work_packages.where(project:).where.not(status_id: Assistant::Facts.closed_status_ids).to_a
            [request, wps] if wps.any?
          end
        end

        def github
          return [] unless defined?(::GithubPullRequest)

          ::GithubPullRequest.where(state: "open").where(draft: [false, nil]).where(merged: [false, nil])
                             .where(id: ::GithubPullRequest.joins(:work_packages).where(work_packages: { project_id: project.id }).select(:id))
                             .to_a
        end

        def gitlab
          return [] unless defined?(::GitlabMergeRequest)

          ::GitlabMergeRequest.where(state: "opened").where(draft: [false, nil]).where(merged: [false, nil])
                              .where(id: ::GitlabMergeRequest.joins(:work_packages).where(work_packages: { project_id: project.id }).select(:id))
                              .to_a
        end

        def reviewer_for(wp)
          author = wp.assigned_to_id
          [wp.responsible, *leads].find { it.is_a?(User) && it.active? && !it.is_a?(AssistantUser) && it.id != author }
        end

        def build(request, packages, reviewer, waited)
          wp = packages.first
          candidate(
            fingerprint: "#{request.class.name}:#{request.id}:#{waited}", recipient: reviewer, subject: wp, nature: :object,
            headline: t("headline", number: request.number, title: request.title.to_s.truncate(50), days: waited),
            because: [t("opened", date: day(request.created_at.to_date), repository: request.repository),
                      t("for", list: packages.map { "##{it.id}" }.join(t("separator")),
                               author: wp.assigned_to&.name || "–")],
            impact: { critical_path: graph.slack(wp.id)&.<=(1) || false, cascade: graph.downstream(wp.id).size, people: 1 },
            facts: { since: request.created_at, waited_working_days: waited, url: url_of(request) },
            steps_for: lambda do |_user|
              [option(t("take", number: request.number), t("take_consequence"), "take_review",
                      [comment(wp, t("take_comment", number: request.number,
                                                     who: wp.assigned_to.is_a?(User) ? mention(wp.assigned_to) : ""))])]
            end
          )
        end

        def url_of(request) = request.try(:github_html_url) || request.try(:gitlab_html_url)
      end
    end
  end
end
