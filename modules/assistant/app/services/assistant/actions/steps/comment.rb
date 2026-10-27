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
      # A comment the assistant posts in its own name on a work package.
      class Comment < Base
        def call(user:, cause:)
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless target
          return take_place(placeholder, cause:) if placeholder

          target.journal_cause = cause
          call = ::AddWorkPackageNoteService.new(user:, work_package: target)
                                            .call(attributes["notes"].to_s, internal: attributes["internal"] == true)
          return Outcome.failure(errors_of(call)) unless call.success?

          journal = target.journals.reload.last
          Outcome.new(success: true, errors: [], touches: [Touch.new(record: journal, changes: {}, created: true)])
        end

        private

        def placeholder
          @placeholder ||= target.journals.find_by(id: step["replace"], user_id: Assistant.user.id) if step["replace"]
        end

        # The line left when the assistant was called becomes the answer.
        def take_place(journal, cause:)
          call = ::Journals::UpdateService.new(model: journal, user: Assistant.user).call(notes: attributes["notes"].to_s)
          return Outcome.failure(errors_of(call)) unless call.success?

          journal.update_columns(cause: cause.to_hash) if cause
          Outcome.new(success: true, errors: [], touches: [Touch.new(record: journal, changes: {}, created: true)])
        end
      end
    end
  end
end
