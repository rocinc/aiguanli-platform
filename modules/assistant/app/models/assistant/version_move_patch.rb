# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  # Journals do not see a work package change versions, and the platform writes
  # the join rows in bulk, so the replacement itself is where the decision
  # moment (S4.1.4) is caught.
  module VersionMovePatch
    private

    def replace_versions(kind, version_ids)
      before = work_package_versions.where(kind:).pluck(:version_id)
      super.tap do
        added = Array(version_ids).map(&:to_i) - before
        if kind == "target" && added.any?
          user = User.current
          ActiveRecord.after_all_transactions_commit { Assistant::VersionMoveAside.after_add(self, added, user) }
        end
      end
    end
  end
end
