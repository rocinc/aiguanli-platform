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
    # Runs the steps through the platform services as the person the action is for,
    # reads every consequence (rescheduled successors, version slips, people
    # affected) and rolls everything back. Running as that person also checks
    # their permission: the assistant can never do more than they could.
    class Preview
      Result = Data.define(:success, :errors, :changes, :affected_user_ids, :version_slips, :cascaded, :notified_user_ids) do
        def to_h
          { "success" => success, "errors" => errors, "changes" => changes, "affected_user_ids" => affected_user_ids,
            "version_slips" => version_slips, "cascaded" => cascaded, "notified_user_ids" => notified_user_ids }
        end
      end

      def initialize(steps:, user:)
        @steps = steps
        @user = user
      end

      def call
        result = nil
        ActiveRecord::Base.transaction(requires_new: true) do
          Journal::NotificationConfiguration.with(false) do
            result = run
          end
          raise ActiveRecord::Rollback
        end
        result
      end

      private

      attr_reader :steps, :user

      def run
        versions_before = {}
        touches = []
        targets = []
        notified = []
        remember_all_versions(versions_before)

        steps.each do |raw|
          step = Steps.for(raw)
          targets << step.target&.to_gid&.to_s
          remember_versions(step.target, versions_before)
          remember_requested_versions(step, versions_before)
          outcome = User.execute_as(user) { step.call(user:, cause: nil) }
          return failure(outcome.errors) unless outcome.success

          touches.concat(outcome.touches)
          notified.concat(outcome.touches.flat_map { recipients_of(it.record) })
        end

        touches.each { remember_versions(it.record, versions_before) }
        build(touches, targets.compact, versions_before, notified)
      end

      def failure(errors)
        Result.new(success: false, errors:, changes: [], affected_user_ids: [], version_slips: [], cascaded: [], notified_user_ids: [])
      end

      def build(touches, targets, versions_before, notified)
        touches = touches.uniq { it.gid }
        changes = touches.map { describe(it) }
        cascaded = touches.select { it.record.is_a?(WorkPackage) && targets.exclude?(it.gid) && !it.created }.map(&:gid)
        affected = touches.flat_map(&:owner_ids).uniq - [user.id, Assistant.user.id]
        Result.new(success: true, errors: [], changes:, affected_user_ids: affected, version_slips: slips(versions_before),
                   cascaded:, notified_user_ids: notified.uniq - [user.id])
      end

      # Whom the platform would notify about something said (kept apart from whose
      # work is affected, which decides who must agree), worked out by the
      # platform's own rules on the journal the step just wrote; the notifications
      # it creates here are rolled back with everything else.
      def recipients_of(record)
        return [] unless Touched::SPOKEN.include?(Touched.kind(record))

        model = record.is_a?(Journal) ? record : (record.try(:journals)&.last || record)
        Notifications::CreateFromModelService.new(model).call(true)
        Notification.where(model.is_a?(Journal) ? { journal: model } : { resource: model }).pluck(:recipient_id)
      end

      def describe(touch)
        record = touch.record
        { "gid" => touch.gid, "type" => record.class.name, "id" => record.id, "kind" => Touched.kind(record),
          "label" => label(touch), "detail" => Touched.detail(record), "anchor" => anchor(touch),
          "created" => touch.created,
          "changes" => touch.changes.transform_values { |pair| pair.map { serialize(it) } } }
      end

      def anchor(touch)
        return if touch.created && touch.record.is_a?(WorkPackage)

        target = Touched.anchor(touch.record)
        { "type" => target.class.name, "id" => target.id } if target
      end

      def label(touch)
        record = touch.record
        return record.subject if touch.created && record.is_a?(WorkPackage)

        Touched.label(record)
      end

      def remember_versions(record, memo)
        return unless record.is_a?(WorkPackage)

        ids = WorkPackageVersion.where(kind: "target", work_package_id: record.id).pluck(:version_id)
        (ids | Array(record.target_version_ids_replacements)).each do |version_id|
          memo[version_id] = finish_of(version_id) unless memo.key?(version_id)
        end
      end

      def remember_all_versions(memo)
        WorkPackageVersion.target.joins(:work_package).group(:version_id).maximum("work_packages.due_date")
                          .each { |version_id, finish| memo[version_id] = finish }
      end

      def remember_requested_versions(step, memo)
        Array(step.attributes["version_id"].presence).each do |version_id|
          memo[version_id.to_i] = finish_of(version_id.to_i) unless memo.key?(version_id.to_i)
        end
      end

      def finish_of(version_id) = WorkPackage.with_target_version(version_id).maximum(:due_date)

      def slips(before)
        before.filter_map do |version_id, was|
          now = finish_of(version_id)
          next if now == was

          version = Version.find_by(id: version_id)
          next unless version

          target = version.effective_date
          { "version_id" => version_id, "name" => version.name, "target" => target&.iso8601,
            "finish_before" => was&.iso8601, "finish_after" => now&.iso8601,
            "late" => target.present? && now.present? && now > target,
            "was_late" => target.present? && was.present? && was > target }
        end
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
