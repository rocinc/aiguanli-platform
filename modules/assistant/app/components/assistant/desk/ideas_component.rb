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
  module Desk
    class IdeasComponent < ApplicationComponent
      include OpPrimer::ComponentHelpers
      include Assistant::QuietWords

      ID = "assistant-desk-ideas"
      FOLDED = %i[adopted set_aside earlier].freeze

      def initialize(project:, user:, read_only: false, focus: nil)
        super()
        @project = project
        @user = user
        @read_only = read_only
        @focus = focus
      end

      attr_reader :project, :user

      def read_only? = @read_only

      def may_convert? = !read_only? && user.allowed_in_project?(:add_work_packages, project)

      def entries
        @entries ||= Assistant::Idea.where(project:).where.not(state: "merged")
                                    .includes(:work_package, mentions: %i[speaker source])
                                    .map { Assistant::Ideas::Entry.new(it, user) }.select(&:shown?).sort_by(&:sort_key)
      end

      def in_section(key) = entries.select { it.section == key }

      def growing = in_section(:growing)

      def folded = FOLDED.select { in_section(it).any? }

      def lead
        parts = []
        parts << t("assistant.ideas.lead_growing", count: growing.size) if growing.any?
        parts << t("assistant.ideas.lead_adopted", count: in_section(:adopted).size) if in_section(:adopted).any?
        parts << t("assistant.ideas.lead_none") if parts.empty?
        t("assistant.ideas.lead", parts: parts.join(t("assistant.ideas.lead_separator")))
      end

      def open_section?(key) = in_section(key).any? { it.idea.id == @focus }

      def merge_targets(entry)
        (growing + in_section(:earlier)).reject { it.idea.id == entry.idea.id }
      end

      def idea_component(entry) = Assistant::Desk::IdeaComponent.new(entry:, ideas: self)
    end
  end
end
