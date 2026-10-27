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
      # A week before a big version ships (03 §6.3, 06 S8): ten minutes of
      # "suppose this release failed — why?". Whoever leads it gets a first
      # list drawn from the facts — the thinnest margins, how defects went in
      # past sprints, decisions still questioned, questions still open — as a
      # slot on the next meeting before the date to go through it. The facts are
      # plain list entries, not checkboxes: nothing in them is a task yet.
      class PreMortem < Base
        WORKING_DAYS_BEFORE = 5
        MIN_WORK_PACKAGES = 5

        def candidates
          project.versions.where(status: "open").where.not(effective_date: nil).flat_map do |version|
            left = Assistant::Facts.working_days_between(today + 1, version.effective_date)
            next [] unless left.between?(1, WORKING_DAYS_BEFORE)

            readiness = Assistant::Facts::VersionReadiness.new(version, today:)
            next [] if readiness.work_packages.size < MIN_WORK_PACKAGES || readiness.open.empty?

            causes = causes(version, readiness)
            next [] if causes.empty?

            leads.map { build(version, causes, it) }
          end
        end

        private

        def build(version, causes, lead)
          meeting = next_meeting(by: version.effective_date)
          candidate(
            fingerprint: version.id.to_s, recipient: lead, subject: version, nature: :team, channel: "brief",
            headline: t("headline", version: version.name, date: day(version.effective_date)),
            because: causes.first(3).map(&:last), impact: { people: people_on(version) },
            act_by: version.effective_date,
            facts: { version_id: version.id, causes: causes.size },
            steps_for: meeting && ->(user) { [agenda_option(version, causes, meeting, user)] }
          )
        end

        def people_on(version) = Assistant::Facts.work_packages_in(version).distinct.count(:assigned_to_id)

        # [[kind, line, refs]], most concrete first.
        def causes(version, readiness)
          ids = readiness.open.map(&:id)
          list = Assistant::Facts::ReleaseRisks.new(readiness, today:, graph:).lines
          history = Assistant::Facts::SprintHistory.new(project, today:).rows
          late = history.filter_map(&:late_share)
          if late.size >= 2 && late.sum / late.size >= 0.5
            list << [:late_defects, t("late_defects", count: late.size, percent: (late.sum * 100 / late.size).round)]
          end
          reopened = defects_reopened
          list << [:reopened, t("reopened", list: refs(reopened))] if reopened.any?
          Assistant::Intent.where(project:, kind: "decision", status: "active", subject_type: "WorkPackage", subject_id: ids)
                            .select(&:contested?).first(2).each do |decision|
            list << [:contested, t("contested", title: decision.title.truncate(50), ref: "##{decision.subject_id}")]
          end
          questions = Assistant::Intent.where(project:, kind: "question", status: "open", subject_type: "WorkPackage", subject_id: ids)
          list << [:questions, t("questions", count: questions.count)] if questions.exists?
          list
        end

        def defects_reopened
          types = Assistant::Facts::SprintHistory.new(project, today:).defect_type_ids
          WorkPackage.where(project:, type_id: types).where(updated_at: 90.days.ago..).select do |wp|
            Assistant::Facts::History.new(wp).changes.any? do |c|
              c.attribute == "status_id" && Assistant::Facts.closed_status_ids.include?(c.from) &&
                Assistant::Facts.closed_status_ids.exclude?(c.to)
            end
          end.first(3)
        end

        def refs(work_packages) = Assistant::Facts::ReleaseRisks.refs(work_packages)

        def agenda_option(version, causes, meeting, user)
          notes = OpenProject::LocaleHelper.with_locale_for(user) do
            [t("agenda_intro", date: day(version.effective_date)), "", *causes.map { "- #{it[1]}" }].join("\n")
          end
          option(t("agenda", meeting: meeting.title.truncate(30)), t("agenda_consequence"), "pre_mortem",
                 [agenda_step(meeting, t("agenda_title", version: version.name), notes, minutes: 10)])
        end
      end
    end
  end
end
