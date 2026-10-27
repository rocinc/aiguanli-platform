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
      class Refused < StandardError; end

      def self.all
        [WorkPackageDetails, Search, Members, CapacityTool, LoadTool, CriticalPath, VersionReadinessTool, SprintTool,
         BudgetTool, CostReport, WhoKnows, History, EstimateTool, WeighRequest, PreviewTool, ProposeTool, Draft, AppraiseTool,
         DocumentTool, InboxTool]
      end

      def self.read_only = all - [ProposeTool]

      # Who is asking, where, about what. Every lookup by a reference the model
      # wrote goes through here and only finds what that person may see.
      class Context
        attr_reader :user, :project, :subject, :conversation

        def initialize(user:, project:, subject: nil, conversation: nil)
          @user = user
          @project = project || subject.try(:project)
          @subject = subject
          @conversation = conversation
        end

        def basis
          return [Assistant::Basis.for(conversation)] if conversation&.persisted?

          subject.respond_to?(:to_gid) ? [Assistant::Basis.for(subject)] : []
        end

        def work_package(ref)
          id = ref.to_s[/\d+/]
          raise Refused, I18n.t("assistant.reasoning.errors.which_work_package") unless id

          wp = WorkPackage.visible(user).find_by(id:)
          raise Refused, I18n.t("assistant.reasoning.errors.not_visible", ref: "##{id}") unless wp

          wp
        end

        def members
          @members ||= begin
            scope = project ? project.users : User.none
            scope.where(status: Principal.statuses[:active]).where.not(type: "AssistantUser").to_a
          end
        end

        def person(ref)
          return user if ref.blank? || ref.to_s.downcase.in?(%w[me myself 我])

          text = ref.to_s.strip.delete_prefix("@").downcase
          found = members.find { it.id.to_s == text } ||
                  members.find { it.login.downcase == text } ||
                  members.find { it.name.downcase == text } ||
                  members.find { it.firstname.to_s.downcase == text } ||
                  members.find { it.name.downcase.include?(text) }
          raise Refused, I18n.t("assistant.reasoning.errors.who", ref:) unless found

          found
        end

        def version(ref)
          versions = project ? project.shared_versions.to_a : []
          text = ref.to_s.strip.downcase
          if text.present?
            found = versions.find { it.id.to_s == text } || versions.find { it.name.downcase == text } ||
                    versions.find { it.name.downcase.include?(text) }
          end
          found ||= nearest_open_version(versions) if text.blank?
          raise Refused, I18n.t("assistant.reasoning.errors.which_version", ref:) unless found

          found
        end

        def sprint(ref)
          sprints = project ? Sprint.where(project:).to_a : []
          text = ref.to_s.strip.downcase
          if text.present?
            found = sprints.find { it.id.to_s == text } || sprints.find { it.name.downcase == text } ||
                    sprints.find { it.name.downcase.include?(text) }
          end
          found ||= Assistant::Facts.current_sprint(project) if text.blank? && project
          raise Refused, I18n.t("assistant.reasoning.errors.which_sprint", ref:) unless found

          found
        end

        def date(value, default: nil)
          return default if value.blank?

          Date.iso8601(value.to_s)
        rescue Date::Error
          raise Refused, I18n.t("assistant.reasoning.errors.date", value:)
        end

        private

        def nearest_open_version(versions)
          versions.select { it.effective_date && it.effective_date >= Date.current && it.status != "closed" }
                  .min_by(&:effective_date)
        end
      end

      class Base
        class << self
          attr_reader :tool_name, :description, :parameters

          def define(name, description, properties = {}, required: [])
            @tool_name = name
            @description = description
            @parameters = { type: "object", properties:, required: }
          end

          def schema = { type: "function", function: { name: tool_name, description:, parameters: } }
        end

        def initialize(context)
          @context = context
        end

        private

        attr_reader :context

        delegate :user, :project, to: :context

        def wp_ref(wp) = { "id" => wp.id, "subject" => wp.subject, "status" => wp.status&.name }

        def person_ref(person) = person && { "id" => person.id, "name" => person.name }

        def iso(date) = date&.iso8601

        def fact_rows(hash) = hash.map { |label, (value, because)| [label, value, because] }
      end
    end
  end
end
