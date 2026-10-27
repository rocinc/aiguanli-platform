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
    module Steps
      # Puts a record back the way it was before an action, through the platform
      # services. Fields someone else has changed since are left alone and
      # reported as conflicts.
      class Revert < Base
        DERIVED = %w[duration derived_estimated_hours derived_remaining_hours derived_done_ratio].freeze

        def call(user:, cause:)
          return Outcome.new(success: true, errors: [], touches: []) if target.nil? && step["created"]
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless target

          step["created"] ? destroy(user) : restore(user, cause)
        end

        def conflicts
          return [] unless target && !step["created"]

          step.fetch("expect", {}).filter_map do |attribute, value|
            attribute if comparable(current(attribute)) != comparable(value)
          end
        end

        private

        def restore(user, cause)
          return restore_links if target.is_a?(::GithubPullRequest)

          attributes = self.attributes.except(*Array(step["skip"]), *DERIVED)
                                      .reject { |name, value| comparable(current(name)) == comparable(value) }
          return Outcome.new(success: true, errors: [], touches: []) if attributes.empty?

          call = case target
                 when WorkPackage
                   params = Steps.work_package_params(attributes).merge("journal_cause" => cause)
                   ::WorkPackages::UpdateService.new(user:, model: target, cause_of_rescheduling: cause)
                                                .call(**params.symbolize_keys)
                 when Project then ::Projects::UpdateService.new(user:, model: target).call(**attributes.symbolize_keys)
                 when Version then ::Versions::UpdateService.new(user:, model: target).call(**attributes.symbolize_keys)
                 when ::WikiPage then ::WikiPages::UpdateService.new(user:, model: target).call(**attributes.slice("text", "title").symbolize_keys)
                 else return Outcome.failure(I18n.t("assistant.actions.errors.not_undoable"))
                 end
          call.success? ? outcome_from(call) : Outcome.failure(errors_of(call))
        end

        def restore_links
          target.update!(work_package_ids: Array(attributes["work_package_ids"]))
          Outcome.new(success: true, errors: [], touches: [])
        end

        def destroy(user)
          service = case target
                    when Relation then ::Relations::DeleteService
                    when WorkPackage then ::WorkPackages::DeleteService
                    when TimeEntry then ::TimeEntries::DeleteService
                    when UserNonWorkingTime then ::UserNonWorkingTimes::DeleteService
                    when ::MeetingOutcome then ::MeetingOutcomes::DeleteService
                    when ::MeetingAgendaItem then ::MeetingAgendaItems::DeleteService
                    else
                      return destroy_allocation(user) if defined?(::ResourceAllocation) && target.is_a?(::ResourceAllocation)
                      return destroy_own(target) if target.is_a?(::Message) || target.is_a?(::WikiPage) || target.is_a?(::Comment)

                      return Outcome.failure(I18n.t("assistant.actions.errors.not_undoable"))
                    end
          call = service.new(user:, model: target).call
          call.success? ? Outcome.new(success: true, errors: [], touches: []) : Outcome.failure(errors_of(call))
        end

        def current(attribute)
          return Steps.version_id_of(target) if attribute == "version_id" && target.is_a?(WorkPackage)

          target.public_send(attribute).then { it.is_a?(Array) ? it.sort : it }
        end

        # The host has no delete service for these; only what the assistant
        # wrote itself is removed.
        def destroy_own(record)
          author_id = record.try(:author_id)
          return Outcome.failure(I18n.t("assistant.actions.errors.not_undoable")) unless author_id == Assistant.user.id

          record.destroy ? Outcome.new(success: true, errors: [], touches: []) : Outcome.failure(Steps.sentences(record.errors))
        end

        def destroy_allocation(user)
          call = ::ResourceAllocations::DeleteService.new(user:, model: target).call
          call.success? ? Outcome.new(success: true, errors: [], touches: []) : Outcome.failure(errors_of(call))
        end

        def comparable(value)
          case value
          when Date, Time, ActiveSupport::TimeWithZone then value.to_date.iso8601
          when BigDecimal, Float then value.to_f
          when nil then nil
          else value.to_s
          end
        end
      end
    end
  end
end
