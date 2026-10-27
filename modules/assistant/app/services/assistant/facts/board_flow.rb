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
  module Facts
    # How work flows across a project's board (04 A5): for each column —
    # a status of a status board, or every open status when the project has
    # none — the cards in it, how many working days each has sat there, and
    # what holds the oldest ones (an open blocker, or the last word said).
    class BoardFlow
      Card = Data.define(:work_package, :days, :blocked_by)
      Column = Data.define(:status, :cards, :limit) do
        def median_days
          sorted = cards.map(&:days).sort
          sorted.empty? ? 0 : sorted[sorted.size / 2]
        end

        def oldest(count = 3) = cards.max_by(count, &:days)

        def over_limit? = limit.present? && cards.size > limit
      end

      def initialize(project, today: Date.current)
        @project = project
        @today = today
      end

      def columns
        @columns ||= statuses.map do |status, limit|
          cards = on_board.select { it.status_id == status.id }.map { card(it) }
          Column.new(status:, cards:, limit:)
        end
      end

      # The current sprint's board when there is one, else the latest.
      def board
        @board ||= begin
          boards = status_boards
          sprint = defined?(::Sprint) && Facts.current_sprint(@project, on: @today)
          boards.find { sprint && it.linked == sprint } || boards.reject { it.linked_type == "Sprint" }.max_by(&:updated_at) ||
            boards.max_by(&:updated_at)
        end
      end

      private

      def open
        @open ||= WorkPackage.where(project: @project).where.not(status_id: Facts.closed_status_ids)
                             .includes(:status, :assigned_to).to_a
      end

      def on_board
        sprint = board&.linked
        sprint.is_a?(::Sprint) ? open.select { it.sprint_id == sprint.id } : open
      end

      def status_boards
        return [] unless defined?(::Boards::Grid)

        ::Boards::Grid.where(project: @project).includes(:widgets).select { it.options.to_h["attribute"] == "status" }
      end

      # [[status, wip limit]]; a column's limit lives in its widget's options when the team set one.
      def statuses
        widgets = board&.widgets&.sort_by(&:start_column) || []
        from_board = widgets.filter_map do |widget|
          ids = Array(widget.options["filters"]).filter_map { it.with_indifferent_access.dig(:status_id, :values) }.flatten
          status = Status.find_by(id: ids.first) if ids.one?
          [status, widget.options["wipLimit"]&.to_i&.nonzero?] if status && !status.is_closed
        end
        return from_board if from_board.any?

        Status.where(id: on_board.map(&:status_id).uniq).order(:position).map { [it, nil] }
      end

      def card(wp)
        since = History.new(wp).entered_status_at.to_date
        Card.new(work_package: wp, days: Facts.working_days_between(since + 1, @today), blocked_by: blocker(wp))
      end

      def blocker(wp)
        ids = Relation.where(to_id: wp.id, relation_type: "blocks").pluck(:from_id) +
              Relation.where(from_id: wp.id, relation_type: "follows").pluck(:to_id)
        WorkPackage.where(id: ids).where.not(status_id: Facts.closed_status_ids).first
      end
    end
  end
end
