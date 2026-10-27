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
    # S5.2: a work package made out of something someone said says so. The
    # "Source" section goes at the end of the description when the proposal
    # is made, so the person deciding reads it too and can change it.
    module SourceNote
      LIMIT = 3
      SOURCES = [Journal, ::Message, ::Comment, ::News, ::WikiPage, MeetingAgendaItem].freeze

      module_function

      def apply(steps, basis)
        sources = sources_of(basis)
        return steps if sources.empty?

        steps.map do |step|
          next step unless step["op"] == "create_work_package"

          attributes = step.fetch("attributes", {})
          next step if present?(attributes["description"], sources)

          step.merge("attributes" => attributes.merge("description" => with_note(attributes["description"], sources)))
        end
      end

      def marker = "**#{I18n.t('assistant.source_note.heading')}**"

      def sources_of(basis)
        Array(basis).filter_map do |entry|
          entry = Assistant::Basis.from_h(entry)
          record = located(entry)
          next unless SOURCES.any? { record.is_a?(it) }
          next if record.try(:internal?)

          url = Assistant::Provenance.url_for_basis(entry.to_h)
          [entry, url] if url
        end.first(LIMIT)
      end

      def label_of(entry)
        record = located(entry)
        return entry.label unless record.is_a?(Journal) && record.journable.is_a?(WorkPackage)

        I18n.t("assistant.source_note.comment", id: record.journable_id, day: Assistant::Text.day(record.created_at.to_date))
      end

      def located(entry)
        entry.record
      rescue ActiveRecord::RecordNotFound
        nil
      end

      def present?(description, sources)
        text = description.to_s
        text.include?(marker) || sources.any? { |_, url| text.include?(url) }
      end

      def with_note(description, sources)
        lines = sources.map do |entry, url|
          link = "[#{label_of(entry)}](#{url})"
          entry.quote.present? ? "> #{entry.quote.squish}\n>\n> — #{link}" : "- #{link}"
        end
        [description.presence, "#{marker}\n\n#{lines.join("\n\n")}"].compact.join("\n\n")
      end
    end
  end
end
