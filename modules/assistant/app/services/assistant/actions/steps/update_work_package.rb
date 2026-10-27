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
      class UpdateWorkPackage < Base
        ALLOWED = %w[subject description start_date due_date duration assigned_to_id responsible_id version_id
                     sprint_id backlog_bucket_id status_id priority_id type_id estimated_hours remaining_hours
                     done_ratio parent_id story_points ignore_non_working_days schedule_manually].freeze

        def call(user:, cause:)
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless target

          params = Steps.work_package_params(attributes.slice(*ALLOWED))
          params["journal_cause"] = cause if cause
          version_before = Steps.version_id_of(target)
          call = ::WorkPackages::UpdateService.new(user:, model: target, cause_of_rescheduling: cause)
                                              .call(**params.symbolize_keys)
          return Outcome.failure(errors_of(call)) unless call.success?

          Steps.with_version_change(outcome_from(call), target, version_before)
        end
      end
    end
  end
end
