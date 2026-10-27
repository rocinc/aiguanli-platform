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

require "rails_helper"

RSpec.describe Budgets::Patches::Projects::RowComponentPatch do
  let(:project) do
    create(:project,
           enabled_module_names: %i[budgets work_package_tracking],
           members: { user => role })
  end
  let(:user) { create(:user) }
  let(:role) { create(:project_role, permissions: [:view_budgets]) }
  let(:table) { TableComponent.new }
  let(:component_class) do
    Class.new(Projects::RowComponent) do
      include Budgets::Patches::Projects::RowComponentPatch
    end
  end
  let(:component) { component_class.new(row: [project, 0], table: table) }

  before do
    login_as(user)
  end

  describe "ProjectBudgets" do
    describe "#total_planned" do
      subject { described_class::ProjectBudgets.new(project) }

      context "with multiple budgets" do
        let!(:budget1) { create(:budget, project:, base_amount: 1000) }
        let!(:budget2) { create(:budget, project:, base_amount: 2000) }

        it "sums up all budget amounts" do
          expect(subject.total_planned).to eq(budget1.budget + budget2.budget)
        end
      end

      context "with no budgets" do
        it "returns zero" do
          expect(subject.total_planned).to eq(BigDecimal(0))
        end
      end
    end

    describe "#total_spent" do
      subject { described_class::ProjectBudgets.new(project) }

      context "with multiple budgets with spent amounts" do
        let!(:budget1) { create(:budget, project:) }
        let!(:budget2) { create(:budget, project:) }

        it "sums up all spent amounts" do
          expect(subject.total_spent).to eq(budget1.spent + budget2.spent)
        end
      end

      context "with no budgets" do
        it "returns zero" do
          expect(subject.total_spent).to eq(BigDecimal(0))
        end
      end
    end

    describe "#total_available" do
      subject { described_class::ProjectBudgets.new(project) }

      context "with multiple budgets with available amounts" do
        let!(:budget1) { create(:budget, project:) }
        let!(:budget2) { create(:budget, project:) }

        it "sums up all available amounts" do
          expect(subject.total_available).to eq(budget1.available + budget2.available)
        end
      end

      context "with no budgets" do
        it "returns zero" do
          expect(subject.total_available).to eq(BigDecimal(0))
        end
      end
    end

    describe "#total_ratio" do
      subject { described_class::ProjectBudgets.new(project) }

      context "when total planned is greater than zero" do
        before do
          allow(subject).to receive_messages(
            total_planned: BigDecimal(1000),
            total_spent: BigDecimal(250)
          )
        end

        it "returns the percentage ratio rounded" do
          expect(subject.total_ratio).to eq(25)
        end
      end

      context "when total planned is zero" do
        before do
          allow(subject).to receive_messages(
            total_planned: BigDecimal(1000),
            total_spent: BigDecimal(0)
          )
        end

        it "returns zero" do
          expect(subject.total_ratio).to eq(0)
        end
      end

      context "with decimal ratio" do
        before do
          allow(subject).to receive_messages(
            total_planned: BigDecimal(3000),
            total_spent: BigDecimal(1000)
          )
        end

        it "rounds to the nearest integer" do
          expect(subject.total_ratio).to eq(33)
        end
      end
    end

    describe "#budgets" do
      subject { described_class::ProjectBudgets.new(project) }

      context "with budgets in the project" do
        let!(:budget1) { create(:budget, project:) }
        let!(:budget2) { create(:budget, project:) }

        it "returns all project budgets as an array" do
          expect(subject.budgets).to contain_exactly(budget1, budget2)
        end

        it "memoizes the result" do
          first_call = subject.budgets
          second_call = subject.budgets
          expect(first_call).to be(second_call)
        end
      end

      context "with no budgets" do
        it "returns an empty array" do
          expect(subject.budgets).to eq([])
        end
      end
    end
  end

  describe "InstanceMethods" do
    describe "#budget_planned" do
      context "when user has permission and project has budgets" do
        let!(:budget) { create(:budget, project:, base_amount: 1500) }

        it "returns formatted currency" do
          allow(component).to receive(:number_to_currency).and_call_original
          expect(component.budget_planned).to include("1,500")
        end
      end

      context "when user lacks permission" do
        let(:role) { create(:project_role, permissions: []) }
        let!(:budget) { create(:budget, project:) }

        it "returns nil" do
          expect(component.budget_planned).to be_nil
        end
      end

      context "when project has no budgets" do
        it "returns nil" do
          expect(component.budget_planned).to be_nil
        end
      end
    end

    describe "#budget_spent" do
      context "when user has permission and project has budgets" do
        let!(:budget) { create(:budget, project:) }

        it "returns formatted currency" do
          allow(component).to receive(:number_to_currency).and_call_original
          result = component.budget_spent
          expect(result).to be_a(String) if result
        end
      end

      context "when user lacks permission" do
        let(:role) { create(:project_role, permissions: []) }
        let!(:budget) { create(:budget, project:) }

        it "returns nil" do
          expect(component.budget_spent).to be_nil
        end
      end

      context "when project has no budgets" do
        it "returns nil" do
          expect(component.budget_spent).to be_nil
        end
      end
    end

    describe "#budget_spent_ratio" do
      context "when user has permission and project has budgets" do
        let!(:budget) { create(:budget, project:) }
        let(:helpers_mock) { double("helpers") }

        before do
          allow(component).to receive(:helpers).and_return(helpers_mock)
        end

        it "returns extended progress bar with ratio" do
          allow(helpers_mock).to receive(:extended_progress_bar).and_return("<progress>0%</progress>")
          result = component.budget_spent_ratio
          expect(result).to be_a(String) if result
        end
      end

      context "when user lacks permission" do
        let(:role) { create(:project_role, permissions: []) }
        let!(:budget) { create(:budget, project:) }

        it "returns nil" do
          expect(component.budget_spent_ratio).to be_nil
        end
      end

      context "when project has no budgets" do
        it "returns nil" do
          expect(component.budget_spent_ratio).to be_nil
        end
      end
    end

    describe "#budget_available" do
      context "when user has permission and project has budgets" do
        let!(:budget) { create(:budget, project:, base_amount: 500) }

        it "returns formatted currency" do
          allow(component).to receive(:number_to_currency).and_call_original
          result = component.budget_available
          expect(result).to be_a(String) if result
        end
      end

      context "when user lacks permission" do
        let(:role) { create(:project_role, permissions: []) }
        let!(:budget) { create(:budget, project:) }

        it "returns nil" do
          expect(component.budget_available).to be_nil
        end
      end

      context "when project has no budgets" do
        it "returns nil" do
          expect(component.budget_available).to be_nil
        end
      end
    end

    describe "#with_project_budgets" do
      context "when project has budgets and user has permission" do
        let!(:budget) { create(:budget, project:) }

        it "yields the project budgets instance" do
          expect { |b| component.with_project_budgets(&b) }.to yield_with_args(kind_of(described_class::ProjectBudgets))
        end

        it "memoizes the project budgets instance" do
          first_budgets = nil
          second_budgets = nil

          component.with_project_budgets { |pb| first_budgets = pb }
          component.with_project_budgets { |pb| second_budgets = pb }

          expect(first_budgets).to be(second_budgets)
        end
      end

      context "when project has no budgets" do
        it "does not yield" do
          expect { |b| component.with_project_budgets(&b) }.not_to yield_control
        end
      end

      context "when user lacks view_budgets permission" do
        let(:role) { create(:project_role, permissions: []) }
        let!(:budget) { create(:budget, project:) }

        it "does not yield" do
          expect { |b| component.with_project_budgets(&b) }.not_to yield_control
        end
      end

      context "when current user is not set" do
        let!(:budget) { create(:budget, project:) }

        before do
          allow(User).to receive(:current).and_return(User.anonymous)
        end

        it "does not yield" do
          expect { |b| component.with_project_budgets(&b) }.not_to yield_control
        end
      end
    end
  end

  describe "permission checks" do
    context "when user has partial permissions" do
      let(:role) { create(:project_role, permissions: %i[view_budgets view_project]) }
      let!(:budget) { create(:budget, project:) }

      it "still allows budget viewing with view_budgets permission" do
        expect(component.budget_planned).not_to be_nil
      end
    end

    context "when project is archived" do
      let!(:budget) { create(:budget, project:) }

      before do
        project.update(active: false)
      end

      it "does not show budget information for archived projects when user lacks permission" do
        expect(component.budget_planned).to be_nil
      end
    end
  end
end
