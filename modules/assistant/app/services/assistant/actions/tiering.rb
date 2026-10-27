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
  module Actions
    # The tier is decided here, from the preview, never by the model.
    module Tiering
      module_function

      IRREVERSIBLE_OPS = %w[delete_work_package publish_news send_mail update_budget change_membership].freeze
      PUBLIC_VOICE_OPS = %w[comment create_wiki_page create_forum_reply create_news_comment].freeze
      # What the whole project reads as its standing; the project lead confirms
      # it every time (04 E1), whatever the team has granted.
      CONFIRMED_OPS = %w[update_project_status].freeze

      def call(action:, preview:)
        ops = action.steps.map { it["op"].to_s }
        return "t0" if ops.empty?
        return "t3" if ops.intersect?(IRREVERSIBLE_OPS)
        return "t2" if ops.intersect?(CONFIRMED_OPS)
        return "t2" if person_voice?(action)
        return "t2" if touches_others?(action, preview)
        return "t2" if edits_someone_elses_page?(action)
        return "t2" if adds_to_someone_elses_meeting?(action)
        return "t2" if ops.intersect?(PUBLIC_VOICE_OPS) && action.on_behalf_of.nil? && !states_facts?(action)

        "t1"
      end

      # Words put in a person's mouth go out only when that person sends them.
      def person_voice?(action)
        action.steps.any? { it["as"] == "person" && PUBLIC_VOICE_OPS.include?(it["op"].to_s) }
      end

      # Replying in a forum topic with what is so ("#12 is planned for 2.1",
      # "this shipped") is the assistant's own voice and allowed from the
      # standard level up (03 §7, 04 D2); the quiet level says nothing in public.
      FACT_KINDS = %w[request_reply follow_up_reply].freeze

      def states_facts?(action)
        return false unless FACT_KINDS.include?(action.kind) && action.project

        Assistant::Preference.effective(nil, action.project).level != "quiet"
      end

      # A new wiki page is the assistant's own draft; changing a page someone
      # else wrote is theirs to agree to (04 D4), unless the team handed the
      # page to the assistant (the decision record duty's page).
      def edits_someone_elses_page?(action)
        action.steps.any? do |step|
          next false unless step["op"] == "create_wiki_page"

          project = Project.find_by(id: step.dig("attributes", "project_id"))
          page = project&.wiki&.find_page(step.dig("attributes", "title"))
          next false unless page

          authors = page.journals.pluck(:user_id).uniq - [Assistant.user.id, action.on_behalf_of_id]
          authors.any? && !handed_over?(project, page)
        end
      end

      # A meeting's agenda is its organiser's; an item they did not ask for,
      # or one that puts someone else up to present, waits for them.
      def adds_to_someone_elses_meeting?(action)
        action.steps.any? do |step|
          next false unless step["op"] == "create_meeting_agenda_item"

          meeting = Meeting.find_by(id: step.dig("attributes", "meeting_id"))
          presenter = step.dig("attributes", "presenter_id").presence&.to_i
          meeting.nil? || meeting.author_id != action.on_behalf_of_id || (presenter && presenter != action.on_behalf_of_id)
        end
      end

      def handed_over?(project, page)
        duty = Assistant::Duty.find_by(project:, kind: "decision_log", active: true)
        duty && (duty.scope.to_h["title"].presence || I18n.t("assistant.duties.decision_log.page_title")) == page.title
      end

      def touches_others?(action, preview)
        return true if Array(preview["cascaded"]).any?
        return true if Array(preview["version_slips"]).any? { it["late"] && !it["was_late"] }
        return true if Array(preview["affected_user_ids"]).any?

        reassigns_someone_else?(action)
      end

      def reassigns_someone_else?(action)
        action.steps.any? do |step|
          next false unless step["op"] == "update_work_package" && step["attributes"].to_h.key?("assigned_to_id")

          current = WorkPackage.find_by(id: step["id"])&.assigned_to_id
          current.present? && current != action.on_behalf_of_id && current != Assistant.user.id
        end
      end

      # A team can say "you don't need to ask me for this kind of thing".
      def lowered_by_grant(action, tier)
        return tier unless tier == "t2" && action.project
        return tier if action.steps.any? { CONFIRMED_OPS.include?(it["op"].to_s) } || person_voice?(action)
        return tier unless Assistant::Grant.live.exists?(project: action.project, action_kind: action.kind)

        "t1"
      end
    end
  end
end
