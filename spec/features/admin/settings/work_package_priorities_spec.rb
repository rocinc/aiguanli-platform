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

require "spec_helper"

RSpec.describe "Work package priorities", :js do
  include Flash::Expectations

  current_user { create(:admin) }
  let!(:default_priority) { create(:issue_priority, is_default: true, name: "Normal") }

  def within_enumeration_item(priority, &)
    page.within("#admin-enumerations-item-component-#{priority.id}", &)
  end

  it "can be managed (created, updated, deleted)" do
    visit admin_settings_work_package_priorities_path

    within_enumeration_item(default_priority) do
      expect(page).to have_content("Normal")
      expect(page).to have_content("Default")
    end

    page.find_test_selector("add-enumeration-button").click

    fill_in "Name", with: "Immediate"
    check "Default"
    click_on("Save")

    expect_and_dismiss_flash(message: "Successful update.")

    # we are redirected back to the index page
    expect(page).to have_current_path(admin_settings_work_package_priorities_path)

    new_priority = IssuePriority.last

    # The new priority is shown in the list as the default priority
    within_enumeration_item(new_priority) do
      expect(page).to have_content("Immediate")
      expect(page).to have_content("Default")
    end

    # Since the new priority is now the default, the former default looses that flag
    within_enumeration_item(default_priority) do
      expect(page).to have_content("Normal")
      expect(page).to have_no_content("Default")
    end

    # It allows editing (Regression #62459)
    click_link "Immediate"

    fill_in "Name", with: "Urgent"
    click_on("Save")

    expect_and_dismiss_flash(message: "Successful update.")

    within_enumeration_item(new_priority) do
      expect(page).to have_content("Urgent")
      expect(page).to have_content("Default")
    end

    expect(IssuePriority).to exist(name: "Urgent")
    expect(IssuePriority).not_to exist(name: "Immediate")

    # It allows deleting priorities
    within_enumeration_item(new_priority) do
      find(test_selector("op-enumeration--action-menu")).click
      click_button("Delete")
    end

    expect_and_dismiss_flash(message: "Successful deletion.")

    expect(page).to have_no_content("Urgent")

    # Since the old default is deleted another is now the default.
    within_enumeration_item(default_priority) do
      expect(page).to have_content("Normal")
      expect(page).to have_no_content("Default")
    end
  end
end
