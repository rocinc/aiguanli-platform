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
    # Who is asking, today's date, the project and the page they are on, put
    # in front of every turn so that "this", "me" and "this sprint" resolve.
    class Situation
      def initialize(user:, project:, subject: nil)
        @user = user
        @project = project || subject.try(:project)
        @subject = subject
      end

      def to_s
        lines = ["## Situation",
                 "Today: #{today.iso8601} (#{today.strftime('%A')}). Working days follow the instance calendar.",
                 "Asking: #{@user.name} (id #{@user.id}, login #{@user.login})#{roles}."]
        lines << project_line if @project
        lines << sprint_line if sprint
        lines << subject_line if @subject
        lines << waiting_line
        lines.compact.join("\n")
      end

      private

      def today = Date.current

      def roles
        return "" unless @project

        names = @user.roles_for_project(@project).map(&:name)
        names.any? ? ", roles: #{names.join(', ')}" : ""
      end

      def project_line
        members = Tools::Context.new(user: @user, project: @project).members
        versions = @project.shared_versions.where(status: "open").map do
          "#{it.name} (#{it.effective_date&.iso8601 || 'no date'})"
        end
        "Project: #{@project.name} (#{@project.identifier}). Members: #{members.map do
          "#{it.name} (id #{it.id})"
        end.join(', ')}. " \
          "Open versions: #{versions.join(', ').presence || 'none'}."
      end

      def sprint = @sprint ||= @project && Assistant::Facts.current_sprint(@project)

      def sprint_line
        "Current sprint: #{sprint.name} #{sprint.start_date&.iso8601}…#{sprint.finish_date&.iso8601}."
      end

      def subject_line
        case @subject
        when WorkPackage
          "Open page: work package ##{@subject.id} \"#{@subject.subject}\" (status #{@subject.status&.name}, " \
          "assignee #{@subject.assigned_to&.name || 'none'}, due #{@subject.due_date&.iso8601 || 'none'})."
        when Journal
          "About comment ##{@subject.id} on ##{@subject.journable_id}: \"#{Assistant::Text.plain(@subject.notes).truncate(300)}\""
        when ::Meeting then "Open page: meeting \"#{@subject.title}\" on #{@subject.start_time&.to_date&.iso8601}."
        when Version then "Open page: version #{@subject.name} due #{@subject.effective_date&.iso8601}."
        when Assistant::Signal, Assistant::Action, Assistant::Intent then Assistant::Conversations::Context.for(@subject).material(@user)
        when ::Message
          "Open page: forum \"#{@subject.forum.name}\", topic \"#{@subject.subject}\" by #{@subject.author&.name} " \
          "(#{@subject.replies_count} replies): \"#{Assistant::Text.plain(@subject.content).truncate(600)}\""
        when ::WikiPage
          "Open page: wiki page \"#{@subject.title}\" (last edited #{@subject.updated_at&.to_date&.iso8601}): " \
          "\"#{Assistant::Text.plain(@subject.text).truncate(1500)}\""
        when ::News
          "Open page: news \"#{@subject.title}\" (#{@subject.created_at.to_date.iso8601}): " \
          "\"#{Assistant::Text.plain(@subject.description).truncate(800)}\""
        else "Open page: #{@subject.class.name} #{@subject.try(:name) || @subject.try(:title) || @subject.try(:id)}."
        end
      end

      def waiting_line
        requests = Assistant::Said.new(@user).requests_for_me.limit(5).to_a
        return nil if requests.empty?

        "Requests waiting for #{@user.name}'s answer: " +
          requests.map {
            "[request_id #{it.id}] \"#{it.quote}\" by #{it.source.try(:user)&.name || it.counterparty&.name} on #{it.subject_type == 'WorkPackage' ? "##{it.subject_id}" : it.subject.try(:title)}"
          }.join("; ")
      end
    end
  end
end
