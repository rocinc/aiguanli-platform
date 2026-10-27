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
      # A resource allocation request for a person on a work package, in the
      # platform's own resource management.
      class CreateResourceAllocation < Base
        def project = WorkPackage.find_by(id: attributes["work_package_id"])&.project

        def call(user:, cause:)
          wp = WorkPackage.find_by(id: attributes["work_package_id"])
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless wp && defined?(::ResourceAllocations::CreateService)

          call = ::ResourceAllocations::CreateService.new(user:).call(
            entity: wp, principal: User.find_by(id: attributes["user_id"]), principal_explicit: true,
            state: attributes["state"].presence || "allocated",
            start_date: attributes["start_date"], end_date: attributes["end_date"],
            allocated_time: (attributes["hours"].to_f * 60).round
          )
          call.success? ? outcome_from(call) : Outcome.failure(errors_of(call))
        end
      end
    end
  end
end
