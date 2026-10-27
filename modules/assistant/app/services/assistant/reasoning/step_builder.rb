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
    # Turns steps as a model writes them ("#69", "Quinn", "Sprint 7", "进行中")
    # into steps the action layer runs (ids only), within what the asking
    # person can see.
    class StepBuilder
      REFERENCES = {
        "assignee" => "assigned_to_id", "assigned_to" => "assigned_to_id", "responsible" => "responsible_id",
        "accountable" => "responsible_id", "version" => "version_id", "sprint" => "sprint_id",
        "status" => "status_id", "priority" => "priority_id", "type" => "type_id", "parent" => "parent_id"
      }.freeze

      PERSONS_WORDS = %w[comment create_forum_reply create_news_comment].freeze

      def initialize(context)
        @context = context
      end

      def call(steps)
        Array(steps).map { build(it.to_h.deep_stringify_keys) }
      end

      private

      attr_reader :context

      def build(raw)
        op = raw["op"].to_s
        raise Tools::Refused, I18n.t("assistant.reasoning.errors.unknown_step", op:) unless Assistant::Actions::Steps::OPS.include?(op)

        step = { "op" => op }
        step["as"] = "person" if PERSONS_WORDS.include?(op)
        attributes = resolve(raw.fetch("attributes", {}).to_h)
        case op
        when "update_work_package", "comment"
          wp = context.work_package(raw["work_package"] || raw["id"])
          step.merge!("type" => "WorkPackage", "id" => wp.id)
          attributes["notes"] = mentions(attributes["notes"]) if op == "comment"
        when "create_work_package"
          attributes["project_id"] ||= context.project&.id
          attributes["description"] = mentions(attributes["description"]) if attributes["description"]
        when "create_relation"
          attributes["from_id"] = context.work_package(attributes["from_id"] || raw["from"]).id
          attributes["to_id"] = context.work_package(attributes["to_id"] || raw["to"]).id
        when "update_project_status"
          step.merge!("type" => "Project", "id" => context.project.id)
        when "update_version"
          step.merge!("type" => "Version", "id" => context.version(raw["version"] || raw["id"]).id)
        when "create_time_entry"
          attributes["work_package_id"] = context.work_package(attributes["work_package_id"] || raw["work_package"]).id
          attributes["user_id"] = context.person(attributes["user_id"] || attributes["user"]).id
          attributes.delete("user")
        when "create_reminder"
          attributes["work_package_id"] = context.work_package(attributes["work_package_id"] || raw["work_package"]).id
          attributes["remind_at"] = remind_at(attributes["remind_at"])
        when "create_non_working_time"
          attributes["user_id"] = context.person(attributes["user_id"] || attributes["user"]).id
          attributes.delete("user")
        when "create_wiki_page"
          attributes["project_id"] ||= context.project&.id
        end
        extra = raw.except("op", "attributes", "work_package", "version", "id", "type", "from", "to")
        step.merge(extra).merge("attributes" => attributes)
      end

      def resolve(attributes)
        attributes.each_with_object({}) do |(key, value), out|
          target = REFERENCES[key] || key
          out[target] = value.nil? || value == "" ? nil : reference(target, value)
        end
      end

      def reference(attribute, value)
        case attribute
        when "assigned_to_id", "responsible_id" then integer?(value) ? value.to_i : context.person(value).id
        when "version_id" then integer?(value) ? value.to_i : context.version(value).id
        when "sprint_id" then integer?(value) ? value.to_i : context.sprint(value).id
        when "status_id" then integer?(value) ? value.to_i : named(Status, value)
        when "priority_id" then integer?(value) ? value.to_i : named(IssuePriority, value)
        when "type_id" then integer?(value) ? value.to_i : named(Type, value)
        when "parent_id" then context.work_package(value).id
        when "start_date", "due_date", "spent_on" then context.date(value).iso8601
        else value
        end
      end

      def integer?(value) = value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/)

      def named(model, value)
        text = value.to_s.strip.downcase
        record = model.all.find { it.name.downcase == text } || model.all.find { it.name.downcase.include?(text) }
        raise Tools::Refused, I18n.t("assistant.reasoning.errors.unknown_value", value:) unless record

        record.id
      end

      # "@Quinn" in text the assistant writes becomes a real mention, so the
      # host notifies that person.
      # "2026-10-12" or "2026-10-12T09:00" in the person's zone; a date alone is
      # their morning.
      def remind_at(value)
        zone = context.user.time_zone || Time.zone
        at = value.to_s.match?(/T\d/) ? zone.parse(value.to_s) : zone.parse("#{value} 09:00")
        raise Tools::Refused, I18n.t("assistant.reasoning.errors.date", value:) unless at && at > Time.current

        at.iso8601
      rescue ArgumentError
        raise Tools::Refused, I18n.t("assistant.reasoning.errors.date", value:)
      end

      def mentions(text)
        return text if text.blank?

        text.to_s.gsub(/(?<![\w@])@([\p{L}\p{N}._-]+(?:\s\p{Lu}\p{L}+)?)/) do |match|
          person = begin
            context.person(Regexp.last_match(1))
          rescue Tools::Refused
            nil
          end
          person ? Assistant::Reasoning::StepBuilder.mention(person) : match
        end
      end

      def self.mention(person)
        name = ERB::Util.html_escape(person.name)
        %(<mention class="mention" data-id="#{person.id}" data-type="user" data-text="@#{name}">@#{name}</mention>)
      end
    end
  end
end
