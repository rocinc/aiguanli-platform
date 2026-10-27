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
  module Ideas
    # One idea as one reader may see it: only the sources they can open are
    # quoted, and an idea whose origin they cannot see does not lend them its
    # title either.
    class Entry
      EARLIER_AFTER = 90.days
      NAMES_SHOWN = 3

      def self.source_label(source)
        case source
        when Journal
          wp = source.journable
          return I18n.t("assistant.ideas.source.work_package", id: wp.id) if wp.is_a?(WorkPackage)

          Assistant::Basis.describe(source)
        when ::MeetingAgendaItem then source.meeting.title.truncate(30)
        else Assistant::Basis.describe(source)
        end
      end

      def self.source_url(source) = Assistant::Provenance.url_for_basis(Assistant::Basis.for(source, label: "").to_h)

      def initialize(idea, user)
        @idea = idea
        @user = user
      end

      attr_reader :idea, :user

      def title
        return @title if defined?(@title)

        @title =
          if visible?(idea.mentions.first&.source) then idea.title
          elsif quotes.any? then quotes.first.quote.truncate(60)
          elsif idea.state == "adopted" && idea.work_package&.visible?(user) then idea.work_package.subject
          end
      end

      def shown? = title.present?

      def quotes
        @quotes ||= idea.mentions.select { visible?(it.source) }.sort_by(&:said_at)
      end

      def hidden_count = idea.mentions.size - quotes.size

      def speakers = @speakers ||= quotes.filter_map(&:speaker).uniq

      def last_said_at = quotes.last&.said_at

      def speakers_text
        names = speakers.map(&:name)
        return I18n.t("assistant.ideas.said_by_nobody") if names.empty?
        return I18n.t("assistant.ideas.said_by", names: names.join("、")) if names.size <= NAMES_SHOWN

        I18n.t("assistant.ideas.said_by_many", names: names.first(2).join("、"), count: names.size)
      end

      def stale?
        idea.state == "open" && (idea.mentions.map(&:said_at).max || idea.created_at) < EARLIER_AFTER.ago
      end

      def section
        case idea.state
        when "adopted" then :adopted
        when "set_aside" then :set_aside
        else stale? ? :earlier : :growing
        end
      end

      def sort_key
        case section
        when :growing, :earlier then [-speakers.size, -last_said_at.to_i, -idea.id]
        else [-idea.updated_at.to_i, -idea.id]
        end
      end

      def work_package_description
        shared = quotes.reject { it.source.try(:internal?) }
        names = shared.filter_map(&:speaker).uniq.map(&:name).join("、")
        lines = shared.reverse.map do |mention|
          I18n.t("assistant.proactive.idea_garden.quote", quote: mention.quote.squish, name: mention.speaker&.name || "–",
                                                          day: Assistant::Text.day(mention.said_at.to_date),
                                                          label: self.class.source_label(mention.source),
                                                          url: self.class.source_url(mention.source))
        end
        I18n.t("assistant.proactive.idea_garden.description", title:, names:, quotes: lines.join("\n\n"))
      end

      def basis
        quotes.last(4).map { Assistant::Basis.for(it.source, quote: it.quote.truncate(200)) }
      end

      private

      def visible?(source)
        case source
        when nil then false
        when Journal then source.journable.present? && source.visible?(user)
        when ::MeetingAgendaItem then source.meeting.visible?(user)
        else source.respond_to?(:visible?) ? source.visible?(user) : false
        end
      end
    end
  end
end
