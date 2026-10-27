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
  # The conversation drawer. It knows the page it was opened on, so "this"
  # means the work package, meeting or project in front of the person.
  class PanelComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers
    include OpTurbo::Streamable

    BODY_ID = "assistant-panel-body"
    HISTORY = 8

    def initialize(user:, conversation: nil, context: nil, project: nil, recent: [], draft: nil)
      super()
      @user = user
      @conversation = conversation
      @context = context
      @project = project || context.try(:project) || (context if context.is_a?(Project))
      @recent = recent
      @draft = draft
    end

    attr_reader :user, :conversation, :context, :project, :recent, :draft

    def wrapper_key = BODY_ID

    def messages
      return [] unless conversation

      @messages ||= conversation.messages.where(role: %w[user assistant]).where.not(status: "tool_round")
                                .select { it.status.in?(%w[streaming stopped]) || it.content.present? }
    end

    def streaming_message = messages.find { it.status == "streaming" }

    def stop_url
      return unless conversation && streaming_message

      url_helpers.assistant_stop_conversation_message_path(conversation, streaming_message)
    end

    def references_url = url_helpers.assistant_references_path

    def form_url
      conversation ? url_helpers.reply_assistant_conversation_path(conversation) : url_helpers.assistant_conversations_path
    end

    def context_gid = (conversation&.context || context)&.to_gid&.to_s

    def subject = conversation&.context || context

    def about = @about ||= Assistant::Conversations::Context.for(subject)

    def thread? = about.present?

    def sync_url = (url_helpers.sync_assistant_conversation_path(conversation) if thread? && conversation)

    def context_removable? = conversation.nil? && subject.present? && !thread?

    def context_lead = thread? ? t("assistant.thread.lead") : t("assistant.panel.context.lead")

    def thread_kind
      return :notice unless about.respond_to?(:kind)

      about.kind(user)
    end

    def thread_welcome = t("assistant.thread.welcome.#{thread_kind == :proposal ? :notice : thread_kind}")

    def chips = thread? && messages.empty? ? about.chips(user) : []

    def context_label
      return about.title(user) if thread?

      case subject
      when WorkPackage then t("assistant.panel.context.work_package", id: subject.id, subject: subject.subject.truncate(50))
      when Meeting then t("assistant.panel.context.meeting", title: subject.title.truncate(50))
      when Project then t("assistant.panel.context.project", name: subject.name)
      end
    end

    def busy? = messages.any? { it.status == "streaming" }

    def name = AssistantUser.instance.name

    delegate :configured?, to: :"Assistant::Llm"

    def object_line
      return unless subject

      @object_line ||= Assistant::ObjectLineComponent.new(object: subject, user:)
    end

    def new_url = url_helpers.assistant_panel_path(context: context_gid, fresh: 1)

    def history
      @history ||= recent.map { HistoryEntry.new(conversation: it, current: it.id == conversation&.id) }
    end

    def history_url(entry) = url_helpers.assistant_panel_path(conversation_id: entry.conversation.id)

    HistoryEntry = Data.define(:conversation, :current) do
      def title = conversation.title.presence || I18n.t("assistant.panel.history.untitled")

      def stamp = Assistant::Text.stamp(conversation.updated_at)

      def about
        label = case conversation.context
                when Assistant::Signal, Assistant::Action, Assistant::Intent then conversation.about.title(conversation.user)
                when WorkPackage then "##{conversation.context.id}"
                when Meeting then conversation.context.title
                when Project then conversation.context.name
                end
        I18n.t("assistant.panel.history.about", subject: label) if label
      end
    end
  end
end
