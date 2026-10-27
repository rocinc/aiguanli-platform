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
      class LinkPullRequest < Base
        def project = WorkPackage.find_by(id: attributes["work_package_id"])&.project

        def call(user:, cause:)
          work_package = WorkPackage.find_by(id: attributes["work_package_id"])
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless target && work_package
          unless user.allowed_in_work_package?(:view_work_packages, work_package)
            return Outcome.failure(I18n.t("assistant.actions.errors.refused"))
          end

          before = target.work_package_ids.sort
          return Outcome.new(success: true, errors: [], touches: []) if before.include?(work_package.id)

          target.work_packages << work_package
          changes = { "work_package_ids" => [before, target.work_package_ids.sort] }
          Outcome.new(success: true, errors: [], touches: [Touch.new(record: target, changes:, created: false)])
        end
      end
    end
  end
end
