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
  module Provenance
    module_function

    def url_for_basis(basis)
      record = Assistant::Basis.from_h(basis).record
      helpers = OpenProject::StaticRouting::StaticUrlHelpers.new
      case record
      when Journal then journal_url(record, helpers)
      when ::Message then message_url(record, helpers)
      when ::Comment then "#{helpers.news_path(record.commented)}#comment-#{record.id}" if record.commented.is_a?(::News)
      when TimeEntry then helpers.cost_reports_path(record.project)
      when ::WikiPage then helpers.project_wiki_path(record.project, record)
      when ::News then helpers.news_path(record)
      when MeetingAgendaItem then "#{helpers.meeting_path(record.meeting)}#agenda-item-#{record.id}"
      when WorkPackage then helpers.work_package_path(record)
      else record.try(:github_html_url).presence
      end
    rescue StandardError
      nil
    end

    def journal_url(journal, helpers)
      case journal.journable
      when WorkPackage then "#{helpers.work_package_path(journal.journable)}/activity#comment-#{journal.id}"
      when ::Message then message_url(journal.journable, helpers)
      when ::WikiPage
        page = journal.journable
        helpers.wiki_diff_project_wiki_path(page.project, page, version: journal.version)
      when ::News then helpers.news_path(journal.journable)
      end
    end

    def message_url(message, helpers)
      root = message.root
      reply = message == root ? {} : { r: message.id, anchor: "message-#{message.id}" }
      helpers.project_forum_topic_path(root.project, root.forum, root, **reply)
    end
  end
end
