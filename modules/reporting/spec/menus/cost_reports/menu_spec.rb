# frozen_string_literal: true

require "spec_helper"

RSpec.describe CostReports::Menu do
  let(:project) { build_stubbed(:project) }
  let(:params) { ActionController::Parameters.new }

  subject(:menu) { described_class.new(project:, params:) }

  describe "#menu_items" do
    let(:fixed_group) { menu.menu_items.first }

    it "always offers the fixed report entries without a header" do
      expect(fixed_group.header).to be_nil
      expect(fixed_group.children.size).to eq(3)
    end

    it "points every fixed entry into the project's cost reports" do
      expect(fixed_group.children.map(&:href))
        .to all(start_with("/projects/#{project.identifier}/reporting/cost_reports"))
    end

    it "marks the default report as selected when nothing is configured" do
      expect(fixed_group.children.map(&:selected)).to eq([true, false, false])
    end

    context "when the time entries preset is requested" do
      let(:params) do
        ActionController::Parameters.new(described_class::PRESETS[:time_entries].transform_values(&:to_s))
      end

      it "selects only that entry" do
        expect(fixed_group.children.map(&:selected)).to eq([false, true, false])
      end
    end
  end
end
