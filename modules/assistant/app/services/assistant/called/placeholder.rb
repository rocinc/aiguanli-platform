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
  module Called
    # The one line the assistant leaves where it was called, in the same request,
    # so the person sees it was heard. The answer later takes its place instead
    # of becoming a second reply. Nobody is notified about the line itself.
    module Placeholder
      module_function

      def post(journal)
        # Called from inside the commenter's own save, whose setting `with` would keep.
        Journal::NotificationConfiguration.send(:with_first, false) do
          case journal.journable
          when WorkPackage then comment(journal)
          when ::Message then reply(journal.journable)
          end
        end
      rescue StandardError => e
        Rails.logger.warn("[assistant] placeholder not posted: #{e.class} #{e.message}")
        nil
      end

      def hold(agenda_item, asker)
        payload = { "headline" => text, "nature" => "answer", "source_gid" => agenda_item.to_gid.to_s, "holding" => true }
        signal = Assistant::Signal.find_or_initialize_by(detector: "mention_answer", recipient: asker,
                                                         fingerprint: "#{agenda_item.to_gid}|answer")
        signal.update!(project: agenda_item.meeting.project, subject: agenda_item.meeting, channel: "inline", state: "pending",
                       score: 40, deliver_at: Time.current, payload:)
        Assistant::SourceSignalsComponent.broadcast_reload(agenda_item, [asker])
        signal
      rescue StandardError => e
        Rails.logger.warn("[assistant] placeholder not held: #{e.class} #{e.message}")
        nil
      end

      def text = I18n.t("assistant.called.mention.placeholder")

      def comment(journal)
        work_package = WorkPackage.find(journal.journable_id)
        call = ::AddWorkPackageNoteService.new(user: Assistant.user, work_package:)
                                          .call(text, send_notifications: false, internal: journal.internal?)
        work_package.journals.reload.where(user: Assistant.user).order(:id).last if call.success?
      end

      def reply(message)
        topic = message.root
        call = ::Messages::CreateService.new(user: Assistant.user)
                                        .call(forum_id: topic.forum_id, parent_id: topic.id,
                                              subject: "RE: #{topic.subject}".truncate(255), content: text)
        call.result if call.success?
      end
    end
  end
end
