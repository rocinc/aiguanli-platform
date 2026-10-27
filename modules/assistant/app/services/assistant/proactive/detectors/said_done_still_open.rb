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
      # Someone said it is fixed or finished (the owner settled a commitment
      # on this work package) and a working day later
      # the work package is still open (03 §3.1, 04 A1). Asked of whoever
      # said it: close it, or say what is left.
      class SaidDoneStillOpen < Base
        GRACE_WORKING_DAYS = 1

        def candidates
          completions.filter_map do |intent, wp|
            next if Assistant::Facts.working_days_between(intent.resolved_at.to_date + 1, today) < GRACE_WORKING_DAYS

            speaker = intent.owner
            next unless speaker.is_a?(User) && speaker.active? && !speaker.is_a?(AssistantUser)

            build(intent, wp, speaker)
          end
        end

        private

        def completions
          Assistant::Intent.where(project:, subject_type: "WorkPackage", kind: %w[commitment deferral], status: "done",
                                  resolved_at: 30.days.ago..)
                           .includes(:subject).order(:resolved_at).filter_map do |intent|
            wp = intent.subject
            [intent, wp] if wp.is_a?(WorkPackage) && Assistant::Facts.open?(wp) && wp.updated_at < intent.resolved_at + 1.hour
          end.uniq { |_, wp| wp.id }
        end

        def build(intent, wp, speaker)
          unmerged = no_merged_change?(wp)
          candidate(
            fingerprint: "#{wp.id}:#{intent.id}", recipient: speaker, subject: wp,
            nature: speaker.id == wp.assigned_to_id ? :own : :object,
            headline: t("headline", ref: "##{wp.id}", status: wp.status.name),
            because: [t("said", title: intent.title.truncate(60), date: day(intent.resolved_at.to_date)),
                      t("still", status: wp.status.name), (t("no_merge") if unmerged)].compact,
            impact: { cascade: graph.downstream(wp.id).size, critical_path: graph.slack(wp.id)&.<=(0) || false,
                      contradiction: unmerged },
            facts: { since: intent.resolved_at, item_id: intent.id },
            steps_for: ->(user) { options(wp, user) }
          )
        end

        def options(wp, user)
          list = []
          status = closing_status(wp, user)
          if status
            list << option(t("close", status: status.name), t("close_consequence"), "close",
                           [step(wp, { "status_id" => status.id })])
          end
          list << option(t("not_yet"), t("not_yet_consequence"), "not_yet", [comment(wp, t("not_yet_comment"))])
          list
        end

        # The project keeps its code next to its work, and this work package
        # has no merged pull or merge request (04 F1 说已修复但没有 PR).
        def no_merged_change?(wp)
          github = project.module_enabled?(:github) && defined?(::GithubPullRequest)
          gitlab = project.module_enabled?(:gitlab) && defined?(::GitlabMergeRequest)
          return false unless github || gitlab

          merged = (github && ::GithubPullRequest.joins(:work_packages).where(work_packages: { id: wp.id }, merged: true).exists?) ||
                   (gitlab && ::GitlabMergeRequest.joins(:work_packages).where(work_packages: { id: wp.id }, state: "merged").exists?)
          !merged
        end

        def closing_status(wp, user)
          ::WorkPackages::UpdateContract.new(wp, user).assignable_statuses.where(is_closed: true).first
        end
      end
    end
  end
end
