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
      # Someone has room in the coming two weeks, and there is something they
      # are good at that nobody does: unassigned backlog work that has waited
      # a while, or an idea several people raised in the idea garden (03 §5,
      # 04 A3). Suggested in the brief of whoever plans the sprint, never as
      # an interruption.
      class IdleCapacity < Base
        MIN_FREE_HOURS = 8
        WAITING_DAYS = 14
        HORIZON_WORKING_DAYS = 9

        def candidates
          to = Assistant::Facts.add_working_days(today, HORIZON_WORKING_DAYS)
          waiting = backlog
          garden = ideas
          return [] if waiting.empty? && garden.empty?

          Routing.assignable(project, on: today).filter_map do |person|
            free = Assistant::Facts::Load.new(person, today, to, today:).free_hours
            next if free < MIN_FREE_HOURS

            match = best_match(person, waiting)
            next idea_candidate(person, free, to, garden) unless match

            wp, evidence = match
            lead = leads.first || person
            candidate(
              fingerprint: "#{person.id}:#{wp.id}:#{today.cweek}", recipient: lead, subject: wp, nature: :opportunity,
              channel: "brief",
              headline: t("headline", name: person.name, hours: free, ref: "##{wp.id}", subject: wp.subject.truncate(30)),
              because: [t("free", name: person.name, hours: free, to: day(to)),
                        t("waiting", ref: "##{wp.id}", days: (today - wp.created_at.to_date).to_i), evidence].compact,
              impact: {}, certainty: :fact,
              steps_for: ->(_user) {
                [option(t("pull", name: person.name), t("pull_consequence"), "pull_in", pull_steps(wp, person))]
              }
            )
          end
        end

        private

        def backlog
          open_work_packages.select do |wp|
            wp.assigned_to_id.nil? && wp.created_at.to_date <= today - WAITING_DAYS && wp.children.none?
          end
        end

        def best_match(person, waiting)
          scored = waiting.filter_map do |wp|
            expert = Assistant::Facts::Expertise.new(project, wp.subject, viewer: person).people(limit: 5).find { it.user == person }
            [expert.score, wp, expert.evidence.first] if expert
          end
          best = scored.max_by(&:first) or return nil
          [best[1], best[2]]
        end

        def ideas
          Assistant::Idea.open.where(project:, work_package_id: nil).includes(:mentions)
                         .select { it.mentions.map(&:speaker_id).uniq.size >= 2 }
        end

        def idea_candidate(person, free, to, garden)
          scored = garden.filter_map do |idea|
            expert = Assistant::Facts::Expertise.new(project, idea.title, viewer: person).people(limit: 5).find { it.user == person }
            [expert, idea] if expert
          end
          best = scored.max_by { it.first.score } or return nil
          expert, idea = best
          lead = leads.first || person
          speakers = idea.mentions.map(&:speaker_id).uniq.size
          candidate(
            fingerprint: "#{person.id}:idea#{idea.id}:#{today.cweek}", recipient: lead, subject: project, nature: :opportunity,
            channel: "brief",
            headline: t("idea_headline", name: person.name, hours: free, title: idea.title.truncate(40)),
            because: [t("free", name: person.name, hours: free, to: day(to)),
                      t("idea_waiting", count: speakers, days: (today - idea.created_at.to_date).to_i), expert.evidence.first].compact,
            impact: {}, facts: { idea_id: idea.id, user_id: person.id },
            steps_for: lambda do |user|
              steps = IdeaGarden.work_package_steps(idea, user)
              steps.first["attributes"]["assigned_to_id"] = person.id
              [option(t("idea_pull", name: person.name), t("pull_consequence"), "idea_to_work_package", steps)]
            end
          )
        end

        def pull_steps(wp, person)
          sprint = Assistant::Facts.current_sprint(project)
          attributes = { "assigned_to_id" => person.id }
          attributes["sprint_id"] = sprint.id if sprint && sprint.finish_date.to_date >= today
          [step(wp, attributes)]
        end
      end
    end
  end
end
