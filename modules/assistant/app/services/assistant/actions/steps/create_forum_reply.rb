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
    module Steps
      # A reply in a forum thread, in the assistant's own name.
      class CreateForumReply < Base
        def project = topic&.forum&.project

        def topic = @topic ||= ::Message.find_by(id: attributes["message_id"])&.then { _1.parent || _1 }

        def call(user:, cause:)
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless topic
          return take_place(placeholder, user) if placeholder

          call = ::Messages::CreateService.new(user:).call(
            forum_id: topic.forum_id, parent_id: topic.id, subject: "RE: #{topic.subject}".truncate(255),
            content: attributes["content"].to_s
          )
          call.success? ? outcome_from(call) : Outcome.failure(errors_of(call))
        end

        private

        def placeholder
          @placeholder ||= topic.children.find_by(id: step["replace"], author_id: Assistant.user.id) if step["replace"]
        end

        # The line left when the assistant was called becomes the answer.
        def take_place(message, user)
          call = ::Messages::UpdateService.new(user:, model: message).call(content: attributes["content"].to_s)
          call.success? ? created_outcome(call) : Outcome.failure(errors_of(call))
        end
      end
    end
  end
end
