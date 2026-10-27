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
  class Drafts
    # Where a draft lands: the thing a person would open to see it. A draft
    # whose target is gone, or not visible to the signer, is not a draft.
    class Target
      Result = Data.define(:label, :url)

      def self.for(step, user) = new(step, user).call

      def initialize(step, user)
        @step = step
        @user = user
      end

      def call
        attrs = @step["attributes"].to_h
        case @step["op"]
        when "comment" then work_package(@step["id"])
        when "create_time_entry" then work_package(attrs["work_package_id"])
        when "create_forum_reply" then message(attrs["message_id"])
        when "create_news_comment" then news(attrs["news_id"])
        when "create_wiki_page" then wiki(attrs["project_id"], attrs["title"])
        when "publish_news" then news_of(attrs["project_id"])
        when "send_mail" then mail_to(attrs)
        when "update_project_status" then project(@step["id"])
        when "create_meeting_outcome" then agenda_item(attrs["agenda_item_id"])
        end
      end

      private

      def work_package(id)
        wp = WorkPackage.visible(@user).find_by(id:) or return
        Result.new("##{wp.id} #{wp.subject.truncate(50)}", helpers.work_package_path(wp))
      end

      def message(id)
        topic = Message.find_by(id:)&.then { it.parent || it }
        return unless topic&.visible?(@user)

        Result.new(topic.subject.truncate(50), helpers.project_forum_topic_path(topic.forum.project, topic.forum, topic))
      end

      def news(id)
        item = News.find_by(id:)
        return unless item&.project && @user.allowed_in_project?(:view_news, item.project)

        Result.new(item.title.truncate(50), helpers.news_path(item))
      end

      def news_of(project_id)
        project = Project.visible(@user).find_by(id: project_id) or return
        Result.new(project.name, helpers.project_news_index_path(project))
      end

      def mail_to(attrs)
        project = Project.visible(@user).find_by(id: attrs["project_id"]) or return
        addresses = Array(attrs["to"])
        return if addresses.empty?

        label = addresses.one? ? addresses.first : I18n.t("assistant.draft.mail_to_many", first: addresses.first, total: addresses.size)
        Result.new(label.truncate(60), helpers.project_path(project))
      end

      def project(id)
        project = Project.visible(@user).find_by(id:) or return
        Result.new(project.name, helpers.project_path(project))
      end

      def wiki(project_id, title)
        project = Project.visible(@user).find_by(id: project_id)
        return unless project&.wiki && title.present?

        Result.new(title.truncate(50), helpers.project_wiki_path(project, WikiPage.slug(title)))
      end

      def agenda_item(id)
        meeting = MeetingAgendaItem.find_by(id:)&.meeting
        return unless meeting&.visible?(@user)

        Result.new(meeting.title.truncate(50), helpers.meeting_path(meeting))
      end

      def helpers = OpenProject::StaticRouting::StaticUrlHelpers.new
    end
  end
end
