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
  module Reasoning
    module Tools
      # Finds things by words in work packages, comments, wiki, meetings,
      # forum posts and what was said and decided. Short Chinese queries match
      # on character bigrams (the same measure the reader uses), everything
      # else by ILIKE.
      class Search < Base
        KINDS = %w[work_packages comments wiki meetings forums decisions said].freeze
        PER_KIND = 6

        define "search",
               "Search the project: work packages, comments (exact quotes), wiki pages, meetings, forum posts, " \
               "decisions and what people said they would do.",
               { query: { type: "string" },
                 kinds: { type: "array", items: { type: "string", enum: KINDS }, description: "Default: all" } },
               required: %w[query]

        def call(args)
          query = args["query"].to_s.strip
          raise Refused, I18n.t("assistant.reasoning.errors.empty_query") if query.blank?

          kinds = Array(args["kinds"]).presence || KINDS
          kinds.index_with { |kind| send(kind, query) }.compact_blank
        end

        private

        def score(text, query)
          down = text.to_s.downcase
          return 1.0 if down.include?(query.downcase)

          share, = Assistant::Text.overlap(text.to_s, query)
          share
        end

        def ranked(records, query, threshold: 0.4)
          records.filter_map { |r, text| [score(text, query), r] if score(text, query) >= threshold }
                 .sort_by { -it.first }.first(PER_KIND).map(&:last)
        end

        def projects = project ? [project] : Project.allowed_to(user, :view_work_packages).to_a

        def work_packages(query)
          candidates = WorkPackage.visible(user).where(project: projects).includes(:status, :assigned_to).limit(500)
          ranked(candidates.map { [it, "#{it.subject} #{Assistant::Text.plain(it.description).first(300)}"] }, query)
            .map { wp_ref(it).merge("assignee" => it.assigned_to&.name, "due" => iso(it.due_date)) }
        end

        def comments(query)
          visible = WorkPackage.visible(user).where(project: projects).select(:id)
          journals = Journal.where(journable_type: "WorkPackage", journable_id: visible).where.not(notes: [nil, ""])
                            .order(created_at: :desc).limit(800).includes(:user).to_a
          journals.reject! { it.internal? && !it.visible?(user) }
          ranked(journals.map { [it, Assistant::Text.plain(it.notes)] }, query).map do |j|
            { "work_package" => j.journable_id, "journal_id" => j.id, "by" => j.user&.name,
              "on" => j.created_at.to_date.iso8601, "quote" => Assistant::Text.plain(j.notes).truncate(300) }
          end
        end

        def wiki(query)
          pages = projects.select { user.allowed_in_project?(:view_wiki_pages, it) }.filter_map(&:wiki).flat_map(&:pages)
          ranked(pages.map { [it, "#{it.title} #{it.text.to_s.first(1500)}"] }, query).map do |page|
            { "title" => page.title, "excerpt" => excerpt(page.text, query) }
          end
        end

        def meetings(query)
          return [] unless defined?(::MeetingAgendaItem)

          meetings = ::Meeting.visible(user).where(project: projects)
          items = ::MeetingAgendaItem.unscoped.where(meeting_id: meetings.select(:id)).includes(:meeting, :outcomes).limit(500)
          ranked(items.map do
            [it, "#{it.title} #{Assistant::Text.plain(it.notes)} #{it.outcomes.map do |o|
              Assistant::Text.plain(o.notes)
            end.join(' ')}"]
          end,
                 query).map do |item|
            { "meeting" => item.meeting.title, "on" => item.meeting.start_time&.to_date&.iso8601, "item" => item.title,
              "notes" => Assistant::Text.plain(item.notes).truncate(300),
              "outcomes" => item.outcomes.map { Assistant::Text.plain(it.notes).truncate(200) } }
          end
        end

        def forums(query)
          forums = ::Forum.where(project: projects.select { user.allowed_in_project?(:view_messages, it) })
          messages = ::Message.where(forum: forums).includes(:author).order(created_at: :desc).limit(300)
          ranked(messages.map { [it, "#{it.subject} #{Assistant::Text.plain(it.content)}"] }, query).map do |m|
            { "subject" => m.subject, "by" => m.author&.name, "on" => m.created_at.to_date.iso8601,
              "excerpt" => Assistant::Text.plain(m.content).truncate(300) }
          end
        end

        def decisions(query)
          scope = Assistant::Intent.visible(user).where(kind: "decision").where.not(status: "dismissed")
          scope = scope.where(project:) if project
          ranked(scope.includes(:owner).map { [it, "#{it.title} #{it.quote}"] }, query).map { item(it) }
        end

        def said(query)
          scope = Assistant::Intent.visible(user).where.not(kind: "decision").where.not(status: "dismissed")
          scope = scope.where(project:) if project
          ranked(scope.includes(:owner, :counterparty).map { [it, "#{it.title} #{it.quote}"] }, query).map { item(it) }
        end

        def item(item)
          { "kind" => item.kind, "status" => item.status, "title" => item.title, "quote" => item.quote,
            "by" => item.owner&.name, "waiting" => item.counterparty&.name, "on" => item.stated_at.to_date.iso8601,
            "due" => iso(item.said_due_on), "where" => item.subject_type == "WorkPackage" ? "##{item.subject_id}" : item.subject.try(:title) }
        end

        def excerpt(text, query)
          plain = text.to_s
          index = plain.downcase.index(query.downcase) || 0
          plain[[index - 80, 0].max, 300]
        end
      end
    end
  end
end
