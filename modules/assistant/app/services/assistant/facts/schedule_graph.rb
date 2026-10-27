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
    # Work packages of a project as a dependency graph: follows/precedes with
    # lag, and blocks, which holds the blocked one back just the same. Used for
    # slack, critical chains and the consequences of moving something.
    class ScheduleGraph
      DEPENDENCY_TYPES = %w[follows precedes blocks].freeze

      Node = Data.define(:id, :subject, :start_date, :due_date, :assignee_id, :version_id, :closed)

      def initialize(project)
        @project = project
      end

      def nodes
        @nodes ||= begin
          rows = WorkPackage.where(project: @project)
                            .pluck(:id, :subject, :start_date, :due_date, :assigned_to_id, :status_id)
          version_ids = Facts.version_ids_of(rows.map(&:first))
          rows.to_h do |id, subject, s, d, a, st|
            [id, Node.new(id:, subject:, start_date: s, due_date: d, assignee_id: a, version_id: version_ids[id],
                          closed: Facts.closed_status_ids.include?(st))]
          end
        end
      end

      # successor_id => [[predecessor_id, lag]]
      def predecessors
        @predecessors ||= edges.each_with_object(Hash.new { |h, k| h[k] = [] }) { |(from, to, lag), h| h[from] << [to, lag] }
      end

      def successors
        @successors ||= edges.each_with_object(Hash.new { |h, k| h[k] = [] }) { |(from, to, lag), h| h[to] << [from, lag] }
      end

      # Everything that follows id, transitively.
      def downstream(id, seen = Set.new)
        successors[id].each do |(succ, _)|
          next if seen.include?(succ)

          seen << succ
          downstream(succ, seen)
        end
        seen
      end

      # Working days a node can slip before it pushes a successor or its
      # version past the version date. Nil when nothing constrains it.
      def slack(id)
        node = nodes[id] or return nil
        return nil unless node.due_date

        limits = successors[id].filter_map do |(succ, lag)|
          s = nodes[succ]
          s&.start_date && (Facts.working_days_between(node.due_date + 1, s.start_date - 1) - lag.to_i)
        end
        if (version = versions[node.version_id]) && version.effective_date
          limits << Facts.working_days_between(node.due_date + 1, version.effective_date)
        end
        limits.min
      end

      # The longest open chain into the version date, from the node whose
      # remaining slack is smallest.
      def critical_chain(version)
        open = nodes.values.select { !it.closed && it.version_id == version.id && it.due_date }
        return [] if open.empty?

        last = open.map(&:due_date).max
        open.select { it.due_date == last }.map { chain_into(it) }.max_by(&:size)
      end

      def versions
        @versions ||= Version.where(id: nodes.values.filter_map(&:version_id).uniq).index_by(&:id)
      end

      private

      def chain_into(tail)
        chain = [tail]
        while (pred = predecessors[chain.first.id].filter_map do |(p, _)|
          nodes[p]
        end.reject(&:closed).max_by { it.due_date || Date.new(0) })
          break if chain.include?(pred)

          chain.unshift(pred)
        end
        chain
      end

      def edges
        @edges ||= Relation.where(relation_type: DEPENDENCY_TYPES)
                           .where(from_id: nodes.keys).or(Relation.where(relation_type: DEPENDENCY_TYPES, to_id: nodes.keys))
                           .pluck(:from_id, :to_id, :lag, :relation_type)
                           .map do |from, to, lag, type|
          if type == "follows"
            [from, to,
             lag]
          else
            [to, from, type == "blocks" ? 0 : lag]
          end
        end
      end
    end
  end
end
