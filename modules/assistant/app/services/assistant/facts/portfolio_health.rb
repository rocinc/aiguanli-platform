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
    # The projects under a portfolio or program, side by side (04 E3): each
    # one's status as set and as the facts suggest it — the nearest version's
    # slip, work past its date, spending ahead of progress — and the people
    # several of them book beyond their hours in the coming weeks.
    class PortfolioHealth
      Row = Data.define(:project, :status_code, :suggested, :reasons)
      Conflict = Data.define(:user, :projects, :load, :capacity)

      HORIZON = 10

      def initialize(portfolio, viewer:, today: Date.current)
        @portfolio = portfolio
        @viewer = viewer
        @today = today
      end

      def projects
        @projects ||= @portfolio.descendants.active.where(workspace_type: "project").select do
          @viewer.allowed_in_project?(:view_project, it)
        end
      end

      def rows = @rows ||= projects.map { row(it) }

      def row_for(project) = row(project)

      def mismatched = rows.select { it.status_code.present? && rank(it.suggested) > rank(it.status_code) }

      # People who work in two or more of these projects with more open work
      # in the next two weeks than hours.
      def conflicts
        @conflicts ||= begin
          to = Facts.add_working_days(@today, HORIZON)
          ids = Member.where(project: projects).group(:user_id).having("COUNT(DISTINCT project_id) >= 2").pluck(:user_id)
          User.active.where(id: ids).where.not(type: "AssistantUser").filter_map do |user|
            load = Load.new(user, @today, to, today: @today)
            capacity = Capacity.new(user, @today, to).hours
            busy = load.entries.map { it.work_package.project }.uniq & projects
            Conflict.new(user:, projects: busy, load: load.hours, capacity:) if busy.size >= 2 && load.hours > capacity
          end
        end
      end

      private

      def rank(code) = %w[on_track at_risk off_track].index(code.to_s) || -1

      def row(project)
        version = project.versions.where(status: "open").where.not(effective_date: nil).order(:effective_date).first
        readiness = version && VersionReadiness.new(version)
        overdue = WorkPackage.where(project:).where.not(status_id: Facts.closed_status_ids).where(due_date: ...@today).count
        burn = BudgetBurn.new(project, viewer: @viewer)
        ahead = burn.planned.positive? && @viewer.allowed_in_project?(:view_budgets, project) ? burn.ahead_of_progress.to_i : 0
        reasons = [(readiness.because if readiness&.at_risk?),
                   (I18n.t("assistant.facts.portfolio.overdue", count: overdue) if overdue.positive?),
                   (I18n.t("assistant.facts.portfolio.ahead", points: ahead) if ahead > 10)].compact
        suggested = if readiness && readiness.slip_days > 3 then "off_track"
                    elsif reasons.any? then "at_risk"
                    else "on_track"
                    end
        Row.new(project:, status_code: project.status_code, suggested:, reasons:)
      end
    end
  end
end
