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
  module Understanding
    # The changes the reader found in one comment or agenda item
    # (`changes` in the extracted payload), tied to real
    # records. A target, person, version or sprint that does not name exactly
    # one thing is dropped: a wrong guess here would move someone's work.
    class SaidChanges
      FIELDS = Assistant::Understanding::Extractor::CHANGE_FIELDS
      CERTAINTIES = %w[certain firm likely].freeze
      NEXT = %w[next 下个 下一个 下个迭代 下迭代 下一个迭代 下版 下一版 下个版本].freeze

      Change = Data.define(:work_package, :field, :attributes, :quote, :certainty, :label) do
        def fingerprint(source) = "#{source.to_gid}|#{work_package.id}|#{field}"

        def certain? = certainty.in?(%w[certain firm])
      end

      def initialize(source, raw)
        @source = source
        @raw = Array(raw)
      end

      attr_reader :source

      def call
        return [] unless target || @raw.any? { it.to_h.stringify_keys["target"].to_s.match?(/\A#\d+\z/) }

        @raw.filter_map { build(it.to_h.stringify_keys) }
      end

      def text
        @text ||= Assistant::Understanding::Sources.text_of(source)
      end

      def target
        @target ||= case source
                    when MeetingAgendaItem then source.work_package || source.outcomes.find(&:linked_work_package?)&.work_package
                    else Assistant::Understanding::Sources.subject_of(source).then { _1 if _1.is_a?(WorkPackage) }
                    end
      end

      def project = Assistant::Understanding::Sources.project_of(source)

      def stated_on = Assistant::Understanding::Sources.stated_at(source).to_date

      def speaker
        person = source.is_a?(MeetingAgendaItem) ? (source.meeting.author || source.presenter || source.author) : Assistant::Understanding::Sources.author_of(source)
        person.is_a?(User) && !person.is_a?(AssistantUser) ? person : nil
      end

      # Shared with Signals: the same rules for what a name or "#12" may mean.
      def resolve_target(ref)
        ref = ref.to_s.strip
        return target if ref.blank? || ref == "this"

        id = ref[/\A#(\d+)\z/, 1]&.to_i or return
        return unless text.scan(/#(\d+)/).flatten.map(&:to_i).include?(id)

        WorkPackage.find_by(id:, project:)
      end

      def person(value)
        id = Integer(value.to_s, exception: false)
        return members.find { it.id == id } if id

        exactly_one(members, value) { |user| [user.name, user.firstname, user.lastname, user.login] }
      end

      private

      def build(data)
        return unless FIELDS.include?(data["field"]) && CERTAINTIES.include?(data["certainty"])

        quote = data["quote"].to_s.strip
        return unless Assistant::Text.contains?(text, quote)

        wp = resolve_target(data["target"]) or return
        attributes = attributes_for(wp, data["field"], data) or return
        return if attributes.all? { |key, value| current(wp, key) == value }

        Change.new(work_package: wp, field: data["field"], attributes:, quote:, certainty: data["certainty"],
                   label: describe(wp, attributes))
      end

      def attributes_for(wp, field, data)
        value = data["value"]
        case field
        when "due_date", "start_date" then dates(wp, field, value, data["shift"] == true)
        when "assignee" then person(value)&.then { { "assigned_to_id" => it.id } }
        when "version" then version(wp, value)&.then { { "version_id" => it.id } }
        when "sprint" then sprint(wp, value)&.then { { "sprint_id" => it.id } }
        when "status" then exactly_one(Status.all, value)&.then { { "status_id" => it.id } }
        when "priority" then exactly_one(IssuePriority.active, value)&.then { { "priority_id" => it.id } }
        when "estimated_hours"
          hours = Float(value, exception: false)
          hours&.positive? ? { "estimated_hours" => hours } : nil
        end
      end

      def dates(wp, field, value, shift)
        due = value.is_a?(Hash) ? value.stringify_keys : {}
        return shifted(wp, field, due) if shift && due["kind"].in?(%w[working_days calendar_days])

        resolved = Assistant::Understanding::DueResolver.new(project:, stated_on:, work_package: wp).call(due)
        return unless resolved.due_on

        result = { field => resolved.due_on.iso8601 }
        result["start_date"] = resolved.due_on.iso8601 if field == "due_date" && wp.start_date && wp.start_date > resolved.due_on
        result
      end

      # "延期一周" moves the work, so both ends move by the same amount.
      def shifted(wp, field, due)
        days = due["value"].to_i
        return if days.zero? || wp.public_send(field).nil?

        move = due["kind"] == "working_days" ? ->(d) { Assistant::Facts.add_working_days(d, days) } : ->(d) { d + days }
        %w[start_date due_date].filter_map { |key| wp.public_send(key)&.then { [key, move.call(it).iso8601] } }.to_h
      end

      def members
        @members ||= project.users.where(status: Principal.statuses[:active]).where.not(type: "AssistantUser").to_a
      end

      def version(wp, value)
        versions = project.shared_versions.where(status: "open").order(:effective_date).to_a
        return exactly_one(versions, value) unless next?(value)

        current = Assistant::Facts.version_of(wp)
        return versions.first if current.nil?

        versions.find { it.effective_date && current.effective_date && it.effective_date > current.effective_date }
      end

      def sprint(wp, value)
        return unless defined?(::Sprint)
        return exactly_one(::Sprint.where(project:).to_a, value) unless next?(value)

        reference = wp.sprint || Assistant::Facts.current_sprint(project, on: stated_on)
        reference && Assistant::Facts.next_sprint(reference)
      end

      def next?(value) = NEXT.include?(value.to_s.strip.downcase)

      def exactly_one(records, value, &names)
        wanted = value.to_s.strip.downcase
        return if wanted.empty?

        names ||= ->(record) { [record.name] }
        found = records.select { |record| Array(names.call(record)).compact.any? { it.to_s.downcase == wanted } }
        found.one? ? found.first : nil
      end

      def current(wp, key)
        value = key == "version_id" ? Assistant::Facts.version_of(wp)&.id : wp.public_send(key)
        value.respond_to?(:iso8601) ? value.iso8601 : value
      end

      def describe(wp, attributes)
        parts = attributes.map do |key, value|
          shown = case key
                  when "assigned_to_id" then User.find_by(id: value)&.name
                  when "version_id" then Version.find_by(id: value)&.name
                  when "sprint_id" then ::Sprint.find_by(id: value)&.name
                  when "status_id" then Status.find_by(id: value)&.name
                  when "priority_id" then IssuePriority.find_by(id: value)&.name
                  when "start_date", "due_date" then Assistant::Text.day(Date.iso8601(value))
                  else value
                  end
          I18n.t("assistant.understanding.fields.#{key}", value: shown)
        end
        "##{wp.id} #{parts.join('，')}"
      end
    end
  end
end
