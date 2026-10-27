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
      class CreateWikiPage < Base
        def project = Project.find_by(id: attributes["project_id"])

        def call(user:, cause:)
          wiki = project&.wiki
          return Outcome.failure(I18n.t("assistant.actions.errors.no_wiki")) unless wiki

          existing = wiki.find_page(attributes["title"])
          call = if existing
                   ::WikiPages::UpdateService.new(user:, model: existing).call(text: attributes["text"],
                                                                               journal_notes: attributes["notes"])
                 else
                   ::WikiPages::CreateService.new(user:).call(wiki:, title: attributes["title"],
                                                              text: attributes["text"], parent_id: attributes["parent_id"])
                 end
          call.success? ? outcome_from(call) : Outcome.failure(errors_of(call))
        end
      end
    end
  end
end
