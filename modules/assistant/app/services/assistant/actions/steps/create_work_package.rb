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
      class CreateWorkPackage < Base
        def project = Project.find_by(id: attributes["project_id"])

        def call(user:, cause:)
          params = attributes.slice("project_id", "type_id", "subject", "description", "start_date", "due_date",
                                    "assigned_to_id", "responsible_id", "version_id", "sprint_id", "priority_id",
                                    "estimated_hours", "parent_id", "status_id", "story_points")
          params["type_id"] ||= project&.enabled_types&.first&.id
          params = Steps.work_package_params(params)
          wp = WorkPackage.new
          wp.journal_cause = cause
          call = ::WorkPackages::CreateService.new(user:).call(**params.symbolize_keys, work_package: wp)
          call.success? ? outcome_from(call) : Outcome.failure(errors_of(call))
        end
      end
    end
  end
end
