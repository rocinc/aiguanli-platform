# frozen_string_literal: true

require "spec_helper"
require_relative "support/pages/cost_report_page"
require_relative "support/components/cost_reports_base_table"

RSpec.describe "Cost report showing time entries with start & end times", :js do
  shared_let(:project) { create(:project) }
  shared_let(:user) { create(:admin) }
  shared_let(:work_package) { create(:work_package, project:) }
  shared_let(:time_entry) do
    create :time_entry, user:, entity: work_package, project:,
                        start_time: 1 * 60,
                        spent_on: 1.day.ago,
                        hours: 1.25,
                        time_zone: "UTC"
  end
  shared_let(:time_entry_long) do
    create :time_entry, user:, entity: work_package, project:,
                        start_time: 1 * 60,
                        hours: 28.0,
                        time_zone: "UTC"
  end
  let(:report_page) { Pages::CostReportPage.new project }
  let(:table) { Components::CostReportsBaseTable.new }

  before do
    login_as(user)
    report_page.visit!
    report_page.clear
    report_page.apply
  end

  context "with allow_tracking_start_and_end_times", with_settings: { allow_tracking_start_and_end_times: true } do
    it "shows the time column" do
      table.expect_sort_header_column("TIME", present: true)
      table.rows_count 2

      table.expect_value("1.25 hours", 1)
      table.expect_cell_text("01:00 AM - 02:15 AM", 1, 2)

      table.expect_value("28.00 hours", 2)
      table.expect_cell_text("01:00 AM - 05:00 AM (+1d)", 2, 2)
    end
  end

  context "without allow_tracking_start_and_end_times", with_settings: { allow_tracking_start_and_end_times: false } do
    it "does not show the time column" do
      table.expect_sort_header_column("TIME", present: false)
      table.rows_count 2
    end
  end
end
