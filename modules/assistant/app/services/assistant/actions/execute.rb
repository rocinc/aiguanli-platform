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
    # Carries out an action as the assistant, through the platform services, with
    # the assistant's cause on every journal. It records how to undo it.
    class Execute
      def self.call(...) = new(...).call

      # Said in public, or the person's own, or sending invitations: not the
      # assistant's to take back.
      NOT_TAKEN_BACK = [Journal, ::News, ::Reminder, ::RecurringMeeting].freeze

      def initialize(action, decided_by:)
        @action = action
        @decided_by = decided_by
      end

      def call
        return action unless action.proposed?

        touches = []
        failure = nil
        ActiveRecord::Base.transaction do
          action.steps.each do |raw|
            step = Steps.for(raw)
            actor = step.in_deciders_name? ? named_person : Assistant.user
            outcome = if actor
                        User.execute_as(actor) { step.call(user: actor, cause: cause_for(step, actor)) }
                      else
                        Steps::Outcome.failure(I18n.t("assistant.actions.errors.needs_a_person"))
                      end
            unless outcome.success
              failure = outcome.errors
              raise ActiveRecord::Rollback
            end
            touches.concat(outcome.touches)
          end

          action.update!(status: "executed", executed_at: Time.current, decided_by:,
                         inverse: inverse_of(touches), journal_ids: journals_of(touches))
        end

        failure ? fail!(failure) : announce
        action
      end

      private

      attr_reader :action, :decided_by

      # Who a step said in a person's name speaks as: whoever confirmed it, or,
      # for T1 done at once, the person it was for, since nobody else decided.
      def cause_for(step, actor)
        Journal::CausedByAssistant.new(action, signed_by: (actor if step.in_deciders_name?))
      end

      def named_person = decided_by || (action.on_behalf_of if action.tier == "t1")

      def fail!(errors)
        action.update!(status: "failed", error: Array(errors).join("; "), decided_by:)
      end

      # Only what the steps changed directly is put back; what the platform moved
      # along with it (successors, parents) is moved back by the platform again.
      def inverse_of(touches)
        direct = action.steps.filter_map { "#{it['type']}/#{it['id']}" if it["id"] }
        touches.uniq(&:gid).reverse.filter_map do |touch|
          record = touch.record
          next if NOT_TAKEN_BACK.any? { record.is_a?(it) }
          next unless touch.created || direct.include?("#{record.class.name}/#{record.id}") || !record.is_a?(WorkPackage)

          if touch.created
            { "op" => "revert", "type" => record.class.name, "id" => record.id, "created" => true,
              "label" => label(record) }
          else
            attributes = touch.changes.transform_values(&:first)
            expect = touch.changes.transform_values(&:last)
            { "op" => "revert", "type" => record.class.name, "id" => record.id, "label" => label(record),
              "attributes" => serialize(attributes), "expect" => serialize(expect) }
          end
        end
      end

      def journals_of(touches)
        ids = Journal.where("cause->>'action_id' = ?", action.id.to_s).pluck(:id)
        ids + touches.filter_map { it.record.id if it.record.is_a?(Journal) }
      end

      def label(record) = Touched.label(record)

      def serialize(hash)
        hash.transform_values do |value|
          case value
          when Date, Time, ActiveSupport::TimeWithZone then value.iso8601
          when BigDecimal then value.to_f
          else value
          end
        end
      end

      def announce
        OpenProject::Notifications.send(:"assistant.action_executed", action:)
      end
    end
  end
end
