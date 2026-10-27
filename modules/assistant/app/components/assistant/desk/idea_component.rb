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
    class IdeaComponent < ApplicationComponent
      include OpPrimer::ComponentHelpers

      def initialize(entry:, ideas:)
        super()
        @entry = entry
        @ideas = ideas
      end

      attr_reader :entry, :ideas

      delegate :idea, :speakers_text, :title, :hidden_count, to: :entry
      delegate :work_package, to: :idea
      delegate :project, :read_only?, :may_convert?, to: :ideas

      def dom_id = "assistant-idea-#{idea.id}"

      def title_id = "#{dom_id}-title"

      def latest = entry.quotes.last

      def others = entry.quotes.reverse.drop(1)

      def more? = others.any? || hidden_count.positive?

      def more_count = others.size + hidden_count

      def day_text(mention) = Assistant::Text.day(mention.said_at.to_date)

      def source_link(mention)
        url = Assistant::Ideas::Entry.source_url(mention.source)
        label = Assistant::Ideas::Entry.source_label(mention.source).truncate(40)
        url ? link_to(label, url, data: { turbo_frame: "_top" }) : label
      end

      def quote_meta(mention)
        safe_join([t("assistant.ideas.meta", name: mention.speaker&.name || t("assistant.ideas.someone"), day: day_text(mention)),
                   source_link(mention)], t("assistant.ideas.meta_separator"))
      end

      def adopted? = entry.section == :adopted

      def set_aside? = entry.section == :set_aside

      def work_package_visible? = work_package&.visible?(ideas.user)

      def work_package_link
        link_to("##{work_package.id} #{work_package.subject.truncate(60)}", url_helpers.work_package_path(work_package),
                data: { turbo_frame: "_top" })
      end

      def restorable? = set_aside? || (adopted? && work_package.nil?)

      def mergeable? = !adopted? && !set_aside? && ideas.merge_targets(entry).any?

      def releasable? = !adopted? && !set_aside?

      def convertible? = releasable? && may_convert?

      def acting? = !read_only?

      def action_path(action) = url_helpers.public_send(:"#{action}_project_assistant_idea_path", project, idea)
    end
  end
end
