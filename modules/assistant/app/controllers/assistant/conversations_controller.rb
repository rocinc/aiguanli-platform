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
  # The conversation drawer. Everything answers inside its turbo frame; while
  # an answer is being written, the message polls `message` for its progress.
  class ConversationsController < ApplicationController
    include OpTurbo::ComponentStream
    include Assistant::ContextLookup

    before_action :require_login
    before_action :find_conversation, only: %i[reply message stop sync]
    before_action :find_context, only: %i[panel create]
    authorization_checked! :create, :reply, :panel, :message, :stop, :sync

    layout false

    def panel
      requested = requested_conversation
      @context = requested.context if requested
      raise ActiveRecord::RecordNotFound if @context && !visible?(@context)

      return render_frame(denied_component) unless allowed_in?(project_of(@context))

      conversation = requested || (recent_conversation_in(@context) if params[:fresh].blank?)
      render_frame(panel_component(conversation))
    end

    def stop
      message = @conversation.messages.find_by(id: params.expect(:message_id), status: "streaming")
      if message
        message.update!(status: "stopped", progress: nil)
        Assistant::Reasoning::Stream.new(@conversation).finished(message)
      end
      head :no_content
    end

    # After an answer settled: what the conversation changed shows on the page
    # behind the panel, in every copy of the thing it was about.
    def sync
      about = @conversation.about
      return head(:no_content) unless about&.visible_to?(current_user) && about.follow(@conversation)

      render turbo_stream: about.copies(current_user).map { |selector, component| turbo_stream.replace_all(selector, component) }
    end

    def create
      return render_frame(denied_component) unless allowed_in?(project_of(@context))

      conversation = Assistant::Conversation.create!(user: current_user, context: @context, project: project_of(@context),
                                                     origin: "panel")
      ask(conversation)
    end

    def reply
      ask(@conversation)
    end

    # The fallback when the socket is down, and the way to fill a gap after a
    # reconnect. JSON answers with the text from `offset` (codepoints) on, so
    # the browser appends without repeating anything; HTML is the message as
    # it should now be rendered.
    def message
      message = @conversation.messages.find(params.expect(:message_id))
      respond_to do |format|
        format.html { render Assistant::MessageComponent.new(message:, user: current_user), layout: false }
        format.json { render json: message_progress(message) }
      end
    end

    private

    def message_progress(message)
      content = message.content.to_s
      offset = params[:offset].to_i.clamp(0, content.length)
      { id: message.id, status: message.status, progress: message.progress, length: content.length,
        offset:, content: content[offset..] }
    end

    def requested_conversation
      current_user_conversations.find(params[:conversation_id]) if params[:conversation_id].present?
    end

    def recent_conversation_in(context)
      return unless context

      current_user_conversations.where(context:).where(updated_at: 12.hours.ago..).recent.first
    end

    def current_user_conversations = Assistant::Conversation.where(user: current_user)

    def find_conversation
      @conversation = current_user_conversations.find(params.expect(:id))
    end

    def find_context
      @context = locate_context(params[:context]) || located_work_package
      raise ActiveRecord::RecordNotFound if @context.nil? && atom_gid?(params[:context])
    end

    def located_work_package
      return if params[:work_package_id].blank?

      WorkPackage.find_by(id: params[:work_package_id])&.then { it if visible?(it) }
    end

    def ask(conversation)
      content = params[:content].to_s.strip.first(4000)
      return render_frame(panel_component(conversation)) if content.blank?
      return render_frame(panel_component(conversation, draft: content)) if busy?(conversation)

      render_frame(panel_component(start_turn(conversation, content)))
    end

    def start_turn(conversation, content)
      message = conversation.messages.create!(role: "user", content:, status: "done")
      Assistant::Reasoning::Turn.start(conversation, message)
      conversation.reload
    end

    def busy?(conversation) = conversation.messages.exists?(status: "streaming")

    def panel_component(conversation, draft: nil)
      Assistant::PanelComponent.new(user: current_user, conversation:, context: conversation&.context || @context,
                                    recent: recent_conversations, draft:)
    end

    def recent_conversations
      current_user_conversations.where(id: Assistant::Message.where(role: "user").select(:conversation_id)).recent
                                .limit(Assistant::PanelComponent::HISTORY).to_a
    end

    def denied_component
      Assistant::PanelUnavailableComponent.new(project: project_of(@context))
    end

    def render_frame(component)
      render html: helpers.turbo_frame_tag(Assistant::PanelDialogComponent::FRAME_ID) {
        render_to_string(component, layout: false)
      }
    end
  end
end
