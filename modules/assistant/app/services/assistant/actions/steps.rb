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
    # Each step kind writes through one host service. A step reports what it
    # touched (record, attribute changes) so that preview, tiering and undo can
    # all work from the same facts.
    module Steps
      Touch = Data.define(:record, :changes, :created) do
        def gid = record.to_gid.to_s

        def owner_ids
          [record.try(:assigned_to_id), record.try(:responsible_id), record.try(:user_id)].compact.uniq
        end
      end

      Outcome = Data.define(:success, :errors, :touches) do
        def self.failure(errors) = new(success: false, errors: Array(errors), touches: [])
      end

      OPS = %w[update_work_package create_work_package create_relation comment update_project_status
               create_time_entry create_non_working_time create_wiki_page update_version create_resource_allocation
               create_meeting_outcome create_meeting_agenda_item create_work_breakdown create_recurring_meeting
               create_forum_reply create_news_comment publish_news create_reminder revert].freeze

      # Steps only the system proposes; the model and the tools never name them.
      SYSTEM_OPS = %w[send_mail link_pull_request].freeze

      # The host keeps a work package's version in work_package_versions; the
      # version_id column is no longer written. Steps keep speaking version_id.
      def self.sentences(errors) = errors.map { sentence_of(it) }

      # A validation message names the attribute it is about; when the platform has
      # no words for that attribute the person still gets a sentence.
      def self.sentence_of(error)
        error.full_message
      rescue I18n::MissingTranslationData
        I18n.t("assistant.actions.errors.refused")
      end

      def self.work_package_params(params)
        return params unless params.key?("version_id")

        version_id = params.delete("version_id")
        params.merge("target_version_ids" => Array(version_id.presence).map(&:to_i))
      end

      def self.version_id_of(work_package)
        WorkPackageVersion.where(kind: "target", work_package_id: work_package.id).order(:id).pick(:version_id)
      end

      def self.with_version_change(outcome, work_package, before)
        after = version_id_of(work_package)
        return outcome if after == before

        touches = outcome.touches.dup
        index = touches.index { it.record == work_package }
        if index
          touches[index] = touches[index].with(changes: touches[index].changes.merge("version_id" => [before, after]))
        else
          touches << Touch.new(record: work_package, changes: { "version_id" => [before, after] }, created: false)
        end
        outcome.with(touches:)
      end

      def self.for(step)
        op = (step["op"] || step[:op]).to_s
        raise ArgumentError, "unknown step #{op}" unless (OPS + SYSTEM_OPS).include?(op)

        const_get(op.camelize).new(step)
      end

      module Recorded
        def call(...) = ChangeLog.capture { super }
      end

      class Base
        def self.inherited(subclass)
          super
          subclass.prepend(Recorded)
        end

        attr_reader :step

        # Public and not taken back: said in the name of the person who
        # confirmed it, never the assistant's (D1 T3, 07 D16).
        def self.in_deciders_name? = false

        # Words that are the person's to say (asking, answering, agreeing,
        # declining) are written as them, by a step marked "as" => "person";
        # facts about the object and the team stay the assistant's (L2.3).
        def in_deciders_name? = self.class.in_deciders_name? || step["as"] == "person"

        def initialize(step)
          @step = step.to_h.deep_stringify_keys
        end

        def attributes = step.fetch("attributes", {})

        def target
          @target ||= step["type"].constantize.find_by(id: step["id"]) if step["type"] && step["id"]
        end

        def project = target.try(:project)

        protected

        def outcome_from(call)
          return Outcome.failure(Steps.sentences(call.errors)) unless call.success?

          touches = call.all_results.compact.uniq.map { touch_of(it) }
          Outcome.new(success: true, errors: [], touches: touches.reject { it.changes.blank? && !it.created })
        end

        def touch_of(record)
          logged = ChangeLog.entry_for(record)
          return Touch.new(record:, changes: record.saved_changes.except(*ChangeLog::IGNORED), created: record.previously_new_record?) unless logged

          Touch.new(record:, changes: logged.changes, created: logged.created)
        end

        # For services that save the record again after creating it (to journal
        # it): by then the record no longer remembers being new.
        def created_outcome(call)
          return Outcome.failure(errors_of(call)) unless call.success?

          Outcome.new(success: true, errors: [], touches: [Touch.new(record: call.result, changes: {}, created: true)])
        end

        def errors_of(call) = call.all_errors.flat_map { Steps.sentences(it) }.uniq
      end
    end
  end
end
