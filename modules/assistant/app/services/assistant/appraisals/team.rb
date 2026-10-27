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
  module Appraisals
    # Everyone in a project over the same period, for medians and rankings.
    # Members without enough data are listed but not ranked.
    class Team
      LOWER_IS_BETTER = %w[quality].freeze
      RANKED = %w[delivery output quality collaboration word knowledge].freeze

      def initialize(project:, from:, to:)
        @project = project
        @from = from
        @to = to
      end

      attr_reader :project, :from, :to

      def members
        @members ||= project.users.where(status: Principal.statuses[:active]).where.not(type: "AssistantUser").to_a
      end

      def profile(user, viewer: nil)
        Profile.new(MemberFacts.new(user:, project:, from:, to:), team: self, viewer:)
      end

      def profiles = @profiles ||= members.map { profile(_1) }

      def median(dimension)
        values = profiles.filter_map { _1.value(dimension) }.sort
        return nil if values.empty?

        mid = values.size / 2
        values.size.odd? ? values[mid] : ((values[mid - 1] + values[mid]) / 2.0).round(2)
      end

      def ranking
        RANKED.index_with do |dimension|
          ranked = profiles.select { _1.value(dimension) }
                           .sort_by { LOWER_IS_BETTER.include?(dimension) ? _1.value(dimension) : -_1.value(dimension) }
          { "order" => ranked.map { { "name" => _1.user.name, "value" => _1.value(dimension) } },
            "not_enough_data" => (profiles - ranked).map { _1.user.name } }
        end
      end
    end
  end
end
