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
  module Conversations
    # What a conversation can be about besides a page: one thing the assistant
    # itself put in front of the person. Each kind says who may talk about it,
    # what the assistant is told about it, and what it is called in the panel.
    class Context
      MATERIAL_LIMIT = 3000
      LINE_LIMIT = 240

      def self.registry
        { "Assistant::Signal" => SignalContext, "Assistant::Action" => ActionContext, "Assistant::Intent" => IntentContext }
      end

      def self.type_names = registry.keys

      def self.for(record) = registry[record.class.name]&.new(record)

      def self.atom?(record) = registry.key?(record.class.name)

      def initialize(record)
        @record = record
      end

      attr_reader :record

      def project = record.project

      def follow(_conversation) = false

      def copies(_user) = []

      def executed_in(conversation)
        ids = conversation.messages.where(role: "assistant").flat_map { card_action_ids(it.cards) }
        Assistant::Action.executed.where(id: ids, on_behalf_of: conversation.user)
      end

      def page_subject = record.subject

      def material(user)
        text = [I18n.t("assistant.thread.material.lead", locale: :en), body(user)].join("\n")
        text.truncate(MATERIAL_LIMIT, separator: "\n")
      end

      private

      def say(key, **) = I18n.t("assistant.thread.material.#{key}", locale: :en, **)

      def line(text) = Assistant::Text.plain(text.to_s).squish.truncate(LINE_LIMIT)

      def describe(subject)
        case subject
        when WorkPackage
          "work package ##{subject.id} \"#{subject.subject}\" (status #{subject.status&.name}, " \
            "assignee #{subject.assigned_to&.name || 'none'}, due #{subject.due_date&.iso8601 || 'none'})"
        when Version then "version #{subject.name} (due #{subject.effective_date&.iso8601 || 'no date'})"
        when Project then "project #{subject.name}"
        when ::Meeting then "meeting \"#{subject.title}\" on #{subject.start_time&.to_date&.iso8601}"
        when nil then nil
        else "#{subject.class.name.demodulize.underscore.humanize.downcase} #{subject.try(:name) || subject.try(:title) || subject.id}"
        end
      end

      def card_action_ids(cards)
        Array(cards).select { it.is_a?(Hash) }.flat_map do |card|
          card["type"] == "options" ? Array(card["items"]).filter_map { it["action_id"] } : [card["action_id"]]
        end.compact.map(&:to_i)
      end

      def option_summary(action, user)
        return unless action

        Assistant::Consequences.new(Assistant::PreviewPresenter.new(action.preview), user:).summary.presence
      rescue StandardError
        nil
      end
    end
  end
end
