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
  module Duties
    # Each merged pull request moves its open work packages to the status the
    # team named for it (scope "status_id"), or the next one in the workflow
    # that reads like review or done. Done right away for the delegator (T1
    # when nothing else moves) and said on the work package.
    class AdvanceMergedPr < Base
      TARGET_NAMES = %w[待验收 测试中 开发完成 review resolved developed 已测试 done].freeze

      def self.due?(duty, now = Time.current) = every(duty, now, 10.minutes)

      TITLE_REFERENCE = /(?<![\w\/#])#(\d+)\b/
      BODY_REFERENCE = /\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)\b/i

      # Only what the pull request spells out as "#81" in its title, or closes by name in its text
      # ("OP#81" is the platform's own link and "(#412)" is the number GitHub adds for the pull request itself).
      def self.mentioned_ids(pr)
        found = pr.title.to_s.scan(TITLE_REFERENCE) + pr.body.to_s.scan(BODY_REFERENCE)
        found.flatten.map(&:to_i).uniq - [pr.number]
      end

      def self.next_status(work_package, preferred_id = nil)
        allowed = WorkPackages::UpdateContract.new(work_package, Assistant.user).assignable_statuses.to_a - [work_package.status]
        return allowed.find { _1.id == preferred_id.to_i } if preferred_id.present?

        position = work_package.status.position.to_i
        TARGET_NAMES.lazy.filter_map { |name| allowed.find { _1.name.downcase.include?(name) && _1.position.to_i > position } }.first
      end

      def call
        return Result.nothing("no_github") unless defined?(::GithubPullRequest)

        ids = unlinked.filter_map { |pr, work_package| link(pr, work_package)&.id }
        ids += merged.flat_map do |pr, work_packages|
          work_packages.filter_map { advance(pr, _1)&.id }
        end
        ids.any? ? Result.new(summary: "#{ids.size}", action_ids: ids, produced: true) : Result.nothing
      end

      private

      def unlinked
        since = duty.last_run_at || 1.day.ago
        ::GithubPullRequest.where(github_updated_at: (since - 1.hour)..).flat_map do |pr|
          self.class.mentioned_ids(pr).filter_map do |id|
            work_package = WorkPackage.find_by(id:, project_id: project.id)
            [pr, work_package] if work_package && pr.work_package_ids.exclude?(id)
          end
        end
      end

      def link(pr, wp)
        return if Assistant::Action.where(kind: "link_pull_request", subject: wp).where("title LIKE ?", "%##{pr.number} %").exists?

        propose(kind: "link_pull_request", subject: wp,
                title: I18n.t("assistant.duties.advance_merged_pr.link_title", number: pr.number, id: wp.id),
                steps: [{ "op" => "link_pull_request", "type" => "GithubPullRequest", "id" => pr.id,
                          "attributes" => { "work_package_id" => wp.id } }])
      end

      def merged
        since = duty.last_run_at || 1.day.ago
        ::GithubPullRequest.where(merged: true).where(merged_at: (since - 1.hour)..)
                           .where(id: ::GithubPullRequest.joins(:work_packages).where(work_packages: { project_id: project.id }).select(:id))
                           .map { [_1, _1.work_packages.where(project:).where.not(status_id: Assistant::Facts.closed_status_ids).to_a] }
      end

      def advance(pr, wp)
        target = self.class.next_status(wp, scope["status_id"])
        return unless target
        return if Assistant::Action.where(kind: "advance_merged_pr", subject: wp).where("title LIKE ?", "%##{pr.number}%").exists?

        notes = I18n.t("assistant.duties.advance_merged_pr.comment", number: pr.number, url: pr.github_html_url, status: target.name)
        action = propose(kind: "advance_merged_pr", subject: wp,
                         title: I18n.t("assistant.duties.advance_merged_pr.title", number: pr.number, id: wp.id, status: target.name),
                         steps: [{ "op" => "update_work_package", "type" => "WorkPackage", "id" => wp.id, "attributes" => { "status_id" => target.id } },
                                 { "op" => "comment", "type" => "WorkPackage", "id" => wp.id, "attributes" => { "notes" => notes } }])
        offer(action, headline: action.title, because: [I18n.t("assistant.duties.advance_merged_pr.because", number: pr.number)], subject: wp)
      end
    end
  end
end
