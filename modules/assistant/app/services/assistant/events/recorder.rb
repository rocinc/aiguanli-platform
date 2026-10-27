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
  module Events
    # Turns the platform's notifications into Assistant::Event rows.
    module Recorder
      module_function

      IGNORED_ATTRIBUTES = %w[updated_at lock_version derived_estimated_hours derived_remaining_hours
                              derived_done_ratio position].freeze

      def subscribe!
        OpenProject::Notifications.subscribe(OpenProject::Events::JOURNAL_CREATED) do |payload|
          record_journal(payload[:journal], payload[:changes])
        end
        OpenProject::Notifications.subscribe(OpenProject::Events::MEMBER_CREATED) do |payload|
          record_member("member_added", payload[:member])
        end
        OpenProject::Notifications.subscribe(OpenProject::Events::MEMBER_DESTROYED) do |payload|
          record_member("member_removed", payload[:member])
        end
      end

      def record_journal(journal, changes)
        return unless journal.is_a?(Journal) && (journable = journal.journable)

        changed = (changes || {}).to_h.except(*IGNORED_ATTRIBUTES).transform_values { |v| Array(v).map { serialize(it) } }
        kind = journal_kind(journal, changed)
        return if kind.nil?

        Event.create!(kind:, subject: journable, project: project_of(journable), actor: journal.user,
                      journal:, changes_made: changed, created_at: journal.created_at)
      rescue StandardError => e
        Rails.logger.error("[assistant] could not record #{journal&.id}: #{e.class} #{e.message}")
      end

      def record_member(kind, member)
        return unless member&.project_id && member.principal.is_a?(User)

        Event.create!(kind:, subject: member.principal, project_id: member.project_id, actor: User.current,
                      changes_made: {}, created_at: Time.current)
      end

      def journal_kind(journal, changed)
        type = journal.journable_type.underscore
        return "#{type}.created" if journal.initial?
        return "#{type}.commented" if journal.notes.present? && changed.empty?
        return "#{type}.updated" if changed.any? || journal.notes.present?

        nil
      end

      def project_of(journable)
        journable.is_a?(Project) ? journable : (journable.try(:project) || journable.try(:wiki)&.project)
      end

      def serialize(value)
        case value
        when Date, Time, ActiveSupport::TimeWithZone then value.iso8601
        when BigDecimal then value.to_f
        else value
        end
      end
    end
  end
end
