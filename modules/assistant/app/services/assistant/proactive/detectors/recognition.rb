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
      # Things worth saying in front of the team (03 §6.5): a version shipped
      # on its date, a long-standing problem finally solved, and the help that
      # never shows on a burndown — answering others, keeping the wiki. Once a
      # week, to whoever leads, with a slot on the next meeting to say it.
      class Recognition < Base
        WEEK = 7
        LONG_DAYS = 30
        MIN_ANSWERS = 3
        MIN_WIKI_EDITS = 5

        def candidates
          return [] if lines.empty?

          meeting = next_meeting(by: Assistant::Facts.add_working_days(today, 5))
          leads.map do |lead|
            candidate(
              fingerprint: "#{today.cwyear}-#{today.cweek}", recipient: lead, subject: project, nature: :team, channel: "brief",
              headline: t("headline", count: lines.size), because: lines.first(6), impact: {},
              facts: { count: lines.size },
              steps_for: meeting && ->(_user) { [agenda_option(meeting, lines)] }
            )
          end
        end

        def lines = @lines ||= [*milestones, *long_solved, *quiet_help]

        private

        def from = today - WEEK

        def milestones
          project.versions.where(status: "closed", effective_date: from..today).filter_map do |version|
            finished = Assistant::Facts.work_packages_in(version).map { closed_on(it) }
            next if finished.empty? || finished.any? { it.nil? || it > version.effective_date }

            t("shipped", version: version.name, date: day(version.effective_date))
          end
        end

        def long_solved
          WorkPackage.where(project:, status_id: Assistant::Facts.closed_status_ids, updated_at: from.beginning_of_day..)
                     .where(created_at: ..LONG_DAYS.days.ago).includes(:assigned_to).filter_map do |wp|
            on = closed_on(wp)
            next unless on && on >= from

            t("solved", ref: "##{wp.id}", subject: wp.subject.truncate(40), days: (on - wp.created_at.to_date).to_i,
                        name: wp.assigned_to&.name || "–")
          end.first(3)
        end

        # Answers to other people's questions and wiki edits, this week.
        def quiet_help
          answers = Assistant::Intent.where(project:, answered_by_type: "Journal", resolved_at: from.beginning_of_day..).to_a
          by_journal = Journal.where(id: answers.map(&:answered_by_id)).pluck(:id, :user_id).to_h
          answered = answers.each_with_object(Hash.new(0)) do |intent, tally|
            user_id = by_journal[intent.answered_by_id]
            tally[user_id] += 1 if user_id && user_id != intent.owner_id
          end
          pages = project.wiki ? Journal.where(journable_type: "WikiPage", journable_id: project.wiki.pages.select(:id))
                                        .where(created_at: from.beginning_of_day..).group(:user_id).count : {}
          people = User.where(id: answered.keys | pages.keys).where.not(type: "AssistantUser").index_by(&:id)
          people.values.filter_map do |person|
            count = answered[person.id]
            edits = pages[person.id].to_i
            next if count < MIN_ANSWERS && edits < MIN_WIKI_EDITS

            t("helped", name: person.name, answers: count, edits:)
          end
        end

        def closed_on(wp)
          change = Assistant::Facts::History.new(wp).changes.reverse.find do
            it.attribute == "status_id" && Assistant::Facts.closed_status_ids.include?(it.to)
          end
          change&.at&.to_date
        end

        def agenda_option(meeting, lines)
          option(t("agenda", meeting: meeting.title.truncate(30)), t("agenda_consequence"), "recognition_agenda",
                 [agenda_step(meeting, t("agenda_title"), lines.map { "- #{it}" }.join("\n"), minutes: 5)])
        end
      end
    end
  end
end
