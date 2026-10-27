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
  module Duties
    # A member joined the project: once the work handed to them in the same
    # sitting is there, their first page about the project is drafted as a
    # wiki page for the delegator to read, edit and publish.
    class Onboarding < Base
      SETTLE = 15.minutes
      KIND = "onboarding_page"

      def self.due?(duty, now = Time.current) = every(duty, now, SETTLE)

      def call
        return Result.nothing("no_wiki") unless project.wiki && project.module_enabled?(:wiki)

        ids = newcomers.filter_map { draft(it) }
        ids.any? ? Result.new(summary: ids.size.to_s, action_ids: ids, produced: true) : Result.nothing
      end

      private

      def newcomers
        from = duty.last_run_at ? duty.last_run_at - SETTLE : duty.created_at
        Member.where(project:, created_at: from..(now - SETTLE)).includes(:principal).filter_map(&:principal).uniq
              .select { it.is_a?(User) && !it.is_a?(AssistantUser) && it.active? && it != delegator }
      end

      def draft(newcomer)
        return if Assistant::Action.exists?(kind: KIND, project:, subject: newcomer)

        OpenProject::LocaleHelper.with_locale_for(delegator) do
          brief = Assistant::Onboarding.new(user: newcomer, project:, today:, llm: (llm if Assistant::Llm.configured?))
          next if brief.empty?

          data = brief.written
          action = propose(kind: KIND, title: I18n.t("assistant.duties.onboarding.title", name: newcomer.name),
                           steps: [{ "op" => "create_wiki_page",
                                     "attributes" => { "project_id" => project.id, "title" => brief.page_title.truncate(250),
                                                       "text" => brief.markdown(data) } }],
                           subject: newcomer, auto_execute: false)
          offer(action, headline: I18n.t("assistant.duties.onboarding.headline", name: newcomer.name), subject: project,
                        because: [data.dig("project", "summary") || data.dig("project", "facts").to_a.first].compact)
          action.id unless action.status == "failed"
        end
      end
    end
  end
end
