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
      # Someone left the project still holding open work, promises or things
      # only they know about (03 §3.1, §8; 04 D2). Whoever leads gets the
      # handover drafted as a wiki page, and for each open work package the
      # person best placed to take it over, by what they know and how much
      # room they have.
      class MemberLeaving < Base
        def candidates
          events("member_removed").filter_map do |event|
            person = event.subject
            next unless person.is_a?(User) && !person.is_a?(AssistantUser)

            handover = Handover.new(person:, project:, today:)
            next if handover.empty?

            lead = (leads - [person]).first or next
            build(event, person, handover, lead)
          end
        end

        private

        def build(event, person, handover, lead)
          candidate(
            fingerprint: "#{person.id}:#{event.id}", recipient: lead, subject: project, nature: :team,
            headline: t("headline", name: person.name, count: handover.work_packages.size),
            because: [(if handover.work_packages.any?
                         t("work", list: handover.work_packages.first(6).map do
                           "##{it.id}"
                         end.join(t("separator")))
                       end),
                      (t("promised", count: handover.promises.size) if handover.promises.any?),
                      (t("knows", list: handover.knowledge.first(3).join(t("separator"))) if handover.knowledge.any?)].compact,
            impact: { cascade: handover.work_packages.size,
                      critical_path: handover.work_packages.any? { graph.slack(it.id)&.<=(0) }, people: 2 },
            facts: { since: event.created_at, user_id: person.id },
            steps_for: ->(user) { options(handover, user) }
          )
        end

        def options(handover, user)
          page = { "op" => "create_wiki_page",
                   "attributes" => { "project_id" => project.id, "title" => t("page", name: handover.person.name).truncate(250),
                                     "text" => OpenProject::LocaleHelper.with_locale_for(user) { handover.markdown } } }
          list = [option(t("draft"), t("draft_consequence"), "handover_page", [page])]
          handover.work_packages.first(3).each do |wp|
            heir = handover.heir_for(wp) or next
            list << option(t("reassign", ref: "##{wp.id}", name: heir.name), t("reassign_consequence", name: heir.name),
                           "reassign", [step(wp, { "assigned_to_id" => heir.id })])
          end
          list
        end

        # What one person leaves behind in a project: their open work, what
        # they promised to whom, and what the team learned from them.
        class Handover
          def initialize(person:, project:, today:)
            @person = person
            @project = project
            @today = today
          end

          attr_reader :person, :project

          def empty? = work_packages.empty? && promises.empty?

          def work_packages
            @work_packages ||= WorkPackage.where(project:).where("assigned_to_id = :id OR responsible_id = :id", id: person.id)
                                          .where.not(status_id: Assistant::Facts.closed_status_ids)
                                          .order(Arel.sql("due_date ASC NULLS LAST")).to_a
          end

          def promises
            @promises ||= Assistant::Intent.live.where(project:, owner: person, kind: %w[commitment deferral])
                                            .includes(:counterparty, :subject).to_a
          end

          # Pages they wrote most of and decisions they made: what to ask them
          # about before they are gone.
          def knowledge
            @knowledge ||= begin
              decisions = Assistant::Intent.where(project:, owner: person, kind: "decision",
                                                   status: "active").limit(5).pluck(:title)
              pages = project.wiki ? project.wiki.pages.where(author_id: person.id).order(updated_at: :desc).limit(5).pluck(:title) : []
              (decisions + pages).map { it.truncate(50) }
            end
          end

          # Whoever knows the subject best among those with room for it.
          def heir_for(wp)
            hours = Assistant::Facts.remaining_hours(wp).nonzero? || 8.0
            to = wp.due_date && wp.due_date > @today ? wp.due_date : Assistant::Facts.add_working_days(@today, 10)
            experts = Assistant::Facts::Expertise.new(project, wp.subject, viewer: Assistant.user).people(limit: 6).map(&:user)
            pool = Routing.assignable(project, on: @today)
            candidates = (experts.select { pool.include?(it) } + pool).uniq.reject { it.id == person.id }
            candidates.find { Assistant::Facts::Load.new(it, @today, to, today: @today).free_hours >= hours }
          end

          def markdown
            helpers = OpenProject::StaticRouting::StaticUrlHelpers.new
            work = work_packages.map do |wp|
              heir = heir_for(wp)
              "- [##{wp.id} #{wp.subject}](#{helpers.work_package_path(wp)}): #{wp.status.name}" \
                "#{", #{Assistant::Text.day(wp.due_date)}" if wp.due_date}" \
                "#{" — #{t('suggested', name: heir.name)}" if heir}"
            end
            promised = promises.map do |item|
              "- #{item.title} (#{item.counterparty&.name || '–'}#{", #{Assistant::Text.day(item.said_due_on)}" if item.said_due_on})"
            end
            sections = [["## #{t('page', name: person.name)}"],
                        ["### #{t('section_work')}", *work], ["### #{t('section_promised')}", *promised],
                        ["### #{t('section_knows')}", *knowledge.map { "- #{it}" }]]
            sections.reject { it.size == 1 && it.first.start_with?("###") }.map { it.join("\n") }.join("\n\n")
          end

          private

          def t(key, **) = I18n.t("assistant.proactive.member_leaving.#{key}", **)
        end
      end
    end
  end
end
