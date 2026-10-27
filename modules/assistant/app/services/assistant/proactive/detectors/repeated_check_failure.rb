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
      # The same check keeps failing across this project's pull requests
      # (04 F1): at least three failures of one check name, on two or more
      # pull or merge requests, in two weeks. Told to whoever leads, with the
      # requests and work packages it hit.
      class RepeatedCheckFailure < Base
        WINDOW = 14.days
        MIN_FAILURES = 3
        MIN_REQUESTS = 2
        FAILED = %w[failure timed_out startup_failure].freeze

        def candidates
          failures.filter_map do |name, runs|
            requests = runs.map(&:first).uniq
            next if runs.size < MIN_FAILURES || requests.size < MIN_REQUESTS

            lead = leads.first or next
            build(name, runs, requests, lead)
          end
        end

        private

        # check name => [[request, run_at, url]]
        def failures
          (github_failures + gitlab_failures).group_by(&:last).transform_values { |runs| runs.map { it.first(3) } }
        end

        def github_failures
          return [] unless defined?(::GithubCheckRun)

          ::GithubCheckRun.where(conclusion: FAILED, completed_at: WINDOW.ago..)
                          .where(github_pull_request_id: linked(::GithubPullRequest))
                          .includes(:github_pull_request)
                          .map { [it.github_pull_request, it.completed_at, it.github_html_url, it.name] }
        end

        def gitlab_failures
          return [] unless defined?(::GitlabPipeline)

          ::GitlabPipeline.where(status: "failed", completed_at: WINDOW.ago..)
                          .where(gitlab_merge_request_id: linked(::GitlabMergeRequest))
                          .includes(:gitlab_merge_request)
                          .map { [it.gitlab_merge_request, it.completed_at, it.gitlab_html_url, it.name] }
        end

        def linked(model)
          model.joins(:work_packages).where(work_packages: { project_id: project.id }).select(:id)
        end

        def build(name, runs, requests, lead)
          wps = requests.flat_map { it.work_packages.where(project:).to_a }.uniq
          candidate(
            fingerprint: "#{name}:#{runs.size}", recipient: lead, subject: project, nature: :team, channel: "brief",
            headline: t("headline", check: name, count: runs.size, requests: requests.size),
            because: [t("requests", list: requests.first(4).map { "##{it.number}" }.join(t("separator"))),
                      (t("work", list: wps.first(4).map { "##{it.id}" }.join(t("separator"))) if wps.any?),
                      t("last", date: day(runs.map { it[1] }.max.to_date))].compact,
            impact: { people: wps.filter_map(&:assigned_to_id).uniq.size, cascade: wps.size },
            facts: { check: name, failures: runs.size, requests: requests.map(&:number), urls: runs.map(&:last).uniq.first(3) }
          )
        end
      end
    end
  end
end
