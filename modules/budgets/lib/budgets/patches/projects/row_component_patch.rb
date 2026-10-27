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

module Budgets::Patches::Projects::RowComponentPatch
  def self.included(base) # :nodoc:
    base.prepend InstanceMethods
  end

  class ProjectBudgets
    attr_reader :project

    def initialize(project)
      @project = project
    end

    delegate :any?, to: :budgets

    def total_planned
      @total_planned ||= budgets.sum(&:budget)
    end

    def total_spent
      @total_spent ||= budgets.sum(&:spent)
    end

    def total_available
      @total_available ||= budgets.sum(&:available)
    end

    def total_ratio
      @total_ratio ||= total_planned.zero? ? 0 : ((total_spent / total_planned) * 100).round
    end

    def budgets
      @budgets ||= project.budgets.to_a
    end
  end

  module InstanceMethods
    def budget_planned
      with_project_budgets do |project_budgets|
        number_to_currency(project_budgets.total_planned, precision: 0)
      end
    end

    def budget_spent
      with_project_budgets do |project_budgets|
        number_to_currency(project_budgets.total_spent, precision: 0)
      end
    end

    def budget_spent_ratio
      with_project_budgets do |project_budgets|
        helpers.extended_progress_bar(project_budgets.total_ratio,
                                      legend: project_budgets.total_ratio.to_s)
      end
    end

    def budget_available
      with_project_budgets do |project_budgets|
        number_to_currency(project_budgets.total_available, precision: 0)
      end
    end

    def with_project_budgets
      @project_budgets ||= ProjectBudgets.new(project)
      return unless @project_budgets.any?
      return unless User.current.allowed_in_project?(:view_budgets, project)

      yield @project_budgets
    end
  end
end
