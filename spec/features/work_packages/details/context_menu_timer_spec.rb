# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Work package single context menu timer", :js do
  shared_let(:project) { create(:project) }
  shared_let(:work_package) { create(:work_package, project:) }

  let(:wp_view) { Pages::FullWorkPackage.new(work_package, project) }

  before do
    login_as(user)
  end

  context "with a user having permission to log time" do
    let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages log_time] }) }

    context "when mobile" do
      include_context "with mobile screen size"

      it "shows the timer entries" do
        wp_view.visit!
        find("#action-show-more-dropdown-menu .button").click

        expect(page).to have_css(".menu-item", text: "Log time")
        expect(page).to have_css(".menu-item", text: "Start timer")
        expect(page).to have_no_css(".menu-item", text: "Stop timer")

        find(".menu-item", text: "Start timer").click
        wait_for_network_idle

        retry_block do
          find("#action-show-more-dropdown-menu .button").click
          expect(page).to have_css(".menu-item", text: "Log time")
          expect(page).to have_css(".menu-item", text: "Stop timer")
          expect(page).to have_no_css(".menu-item", text: "Start timer")
        end
      end
    end

    context "when not mobile" do
      it "does not show the timer entries" do
        wp_view.visit!
        find("#action-show-more-dropdown-menu .button").click

        expect(page).to have_css(".menu-item", text: "Log time")
        expect(page).to have_no_css(".menu-item", text: "Start timer")
        expect(page).to have_no_css(".menu-item", text: "Stop timer")
      end
    end
  end

  context "when user does not have permission to log time" do
    let(:user) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }

    it "does not show the timer entries" do
      wp_view.visit!
      find("#action-show-more-dropdown-menu .button").click

      expect(page).to have_no_css(".menu-item", text: "Log time")
      expect(page).to have_no_css(".menu-item", text: "Start timer")
      expect(page).to have_no_css(".menu-item", text: "Stop timer")
    end
  end
end
