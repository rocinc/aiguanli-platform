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
  module Facts
    # Work packages in a project whose title shares most of its words with
    # another title, newest evidence first; used both for a title being typed
    # and for one just saved.
    module SimilarSubjects
      LOOKBACK = 180.days
      MIN_MATCH = 80

      module_function

      def find(project:, type_id:, subject:, except: [])
        scope = WorkPackage.where(project:, type_id:, created_at: LOOKBACK.ago..).where.not(id: except)
        found = scope.includes(:status, :assigned_to).filter_map do |other|
          share = [Assistant::Text.overlap(subject, other.subject).first,
                   Assistant::Text.overlap(other.subject, subject).first].min
          [other, share] if share >= MIN_MATCH.fdiv(100)
        end
        found.sort_by { |other, share| [-share, Assistant::Facts.open?(other) ? 0 : 1] }
      end
    end
  end
end
