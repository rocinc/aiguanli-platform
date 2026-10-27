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
      class CreateRelation < Base
        def project = WorkPackage.find_by(id: attributes["from_id"])&.project

        def call(user:, cause:)
          from = WorkPackage.find_by(id: attributes["from_id"])
          to = WorkPackage.find_by(id: attributes["to_id"])
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless from && to

          call = ::Relations::CreateService.new(user:).call(
            from:, to:, relation_type: attributes["relation_type"] || "follows",
            lag: attributes["lag"], description: attributes["description"]
          )
          call.success? ? outcome_from(call) : Outcome.failure(errors_of(call))
        end
      end
    end
  end
end
