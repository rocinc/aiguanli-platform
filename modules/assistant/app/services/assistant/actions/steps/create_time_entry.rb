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
      class CreateTimeEntry < Base
        def self.in_deciders_name? = true

        def project = WorkPackage.find_by(id: attributes["work_package_id"])&.project

        def call(user:, cause:)
          wp = WorkPackage.find_by(id: attributes["work_package_id"])
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless wp

          owner = User.find(attributes["user_id"])
          params = { entity: wp, project: wp.project, hours: attributes["hours"], spent_on: attributes["spent_on"] || Date.current,
                     comments: attributes["comments"], activity_id: attributes["activity_id"] }
          params[:user] = owner unless owner == user
          call = ::TimeEntries::CreateService.new(user:).call(**params)
          call.success? ? outcome_from(call) : Outcome.failure(errors_of(call))
        end
      end
    end
  end
end
