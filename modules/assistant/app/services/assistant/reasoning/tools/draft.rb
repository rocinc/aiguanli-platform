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
      # Gives the model the template and the material for a piece of writing.
      # The model writes; putting it into the project goes through propose.
      class Draft < Base
        KINDS = %w[work_package user_story test_cases wiki_page release_notes minutes status_report reply decision_record
                   onboarding handover summary pr_description translation].freeze

        define "draft",
               "Template and material for writing: work_package, user_story, test_cases, wiki_page, release_notes, " \
               "minutes, status_report, reply, decision_record, onboarding, handover, summary (of a work package's " \
               "discussion, a forum topic or a wiki page), pr_description (for a work package), translation " \
               "(of a work package, forum post or wiki page; give the target language in `to`).",
               { kind: { type: "string", enum: KINDS },
                 about: { type: "string",
                          description: "Work package (\"#69\"), version, meeting id, \"forum:<message id>\", \"wiki:<title>\" or a topic" },
                 to: { type: "string", description: "For translation: the target language, e.g. en, zh-CN, de" } },
               required: %w[kind]

        def call(args)
          kind = args["kind"].to_s
          raise Refused, I18n.t("assistant.reasoning.errors.unknown_value", value: kind) unless KINDS.include?(kind)

          template = I18n.t("assistant.templates.#{kind}", to: args["to"].presence || I18n.locale.to_s)
          { "template" => template, "material" => material(kind, args["about"]) }
        end

        private

        def material(kind, about)
          case kind
          when "release_notes", "status_report"
            version = if about.present?
                        begin
                          context.version(about)
                        rescue StandardError
                          nil
                        end
                      end
            status_material(version)
          when "minutes"
            meeting_material(about)
          when "onboarding", "handover"
            person = about.present? ? context.person(about) : user
            person_material(person)
          when "pr_description"
            pr_material(context.work_package(about))
          else
            return forum_material(about) if about.to_s.start_with?("forum:")
            return wiki_material(about) if about.to_s.start_with?("wiki:")

            about.to_s.match?(/\A#?\d+\z/) ? work_package_material(context.work_package(about)) : { "topic" => about }
          end
        end

        def work_package_material(wp)
          WorkPackageDetails.new(context).call("ref" => wp.id.to_s)
                            .merge("children" => wp.children.map { wp_ref(it) }, "discussion" => thread_of(wp),
                                   "related_wiki" => Search.new(context).call("query" => wp.subject, "kinds" => %w[wiki])["wiki"])
        end

        # The whole thread, so a summary or a translation reads what was said.
        def thread_of(wp)
          wp.journals.where.not(notes: [nil, ""]).includes(:user).order(:version).last(60).filter_map do |journal|
            next unless journal.visible?(user)

            { "by" => journal.user&.name, "on" => iso(journal.created_at.to_date), "text" => Assistant::Text.plain(journal.notes).truncate(1500) }
          end
        end

        def forum_material(about)
          message = ::Message.find_by(id: about.to_s.delete_prefix("forum:")[/\d+/])
          raise Refused, I18n.t("assistant.reasoning.errors.not_found") unless message&.visible?(user)

          root = message.root
          { "topic" => root.subject, "forum" => root.forum.name,
            "posts" => [root, *root.children.order(:created_at)].first(80).map do
              { "by" => it.author&.name, "on" => iso(it.created_at.to_date), "text" => Assistant::Text.plain(it.content).truncate(1500) }
            end }
        end

        def wiki_material(about)
          title = about.to_s.delete_prefix("wiki:").strip
          page = project&.wiki&.find_page(title)
          raise Refused, I18n.t("assistant.reasoning.errors.not_found") unless page&.visible?(user)

          { "page" => page.title, "text" => Assistant::Text.plain(page.text).truncate(12_000),
            "updated" => iso(page.updated_at.to_date) }
        end

        # What the change is for and what it touches; the diff itself is the
        # developer's to describe, so the template asks only for what the
        # work package knows.
        def pr_material(wp)
          work_package_material(wp).merge(
            "acceptance" => Assistant::Text.plain(wp.description).scan(/^\s*(?:[-*]\s*\[ \]|☐)\s*(.+)$/).flatten,
            "discussion" => thread_of(wp).last(15)
          )
        end

        def status_material(version)
          week = (Date.current - 7)..Date.current
          closed = WorkPackage.where(project:).where(status_id: Assistant::Facts.closed_status_ids).where(updated_at: week.first.beginning_of_day..)
          {
            "version" => version && VersionReadinessTool.new(context).call("version" => version.id.to_s),
            "closed_this_week" => closed.map { wp_ref(it) },
            "budget" => begin
              Assistant::Facts::BudgetBurn.new(project, viewer: user).to_h.slice("spent_percent", "done_percent",
                                                                                 "because")
            rescue StandardError
              nil
            end,
            "open_decisions" => Assistant::Intent.visible(user).where(project:, kind: "question",
                                                                       status: "open").limit(10).map(&:title),
            "versions" => project.versions.where(status: "open").map do
              VersionReadinessTool.new(context).call("version" => it.id.to_s)
            end
          }
        end

        def meeting_material(about)
          meeting = ::Meeting.visible(user).where(project:).find_by(id: about.to_s[/\d+/]) || ::Meeting.visible(user).where(project:).order(start_time: :desc).first
          return {} unless meeting

          { "meeting" => meeting.title, "on" => meeting.start_time&.to_date&.iso8601,
            "items" => meeting.agenda_items.map do |item|
              { "title" => item.title, "notes" => Assistant::Text.plain(item.notes),
                "outcomes" => item.outcomes.map { Assistant::Text.plain(it.notes) } }
            end,
            "said" => Assistant::Intent.visible(user).where(subject: meeting).map { { "kind" => it.kind, "title" => it.title, "owner" => it.owner&.name } } }
        end

        def person_material(person)
          open = WorkPackage.visible(user).where(project:, assigned_to_id: person.id).where.not(status_id: Assistant::Facts.closed_status_ids)
          { "person" => person.name, "open_work_packages" => open.map { wp_ref(it).merge("due" => iso(it.due_date)) },
            "commitments" => Assistant::Intent.visible(user).live.where(project:, owner: person).map(&:title),
            "decisions" => Assistant::Intent.visible(user).where(project:, kind: "decision", status: "active").order(stated_at: :desc).limit(6).map(&:title),
            "wiki" => project.wiki&.pages&.order(updated_at: :desc)&.limit(8)&.pluck(:title) }
        end
      end
    end
  end
end
