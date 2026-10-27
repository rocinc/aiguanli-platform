# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

RSpec.describe "The assistant's picture", type: :rails_request do
  it "follows the system preference when the application has no say" do
    get "/assistant/avatar"

    expect(response.body).to include("prefers-color-scheme: dark")
  end

  it "stays light when the application theme is light" do
    get "/assistant/avatar", params: { theme: "light" }

    expect(response.body).not_to include("prefers-color-scheme")
    expect(response.body).to include(Assistant::AvatarsController::LIGHT[:disc])
  end

  it "uses the dark colours when the application theme is dark" do
    get "/assistant/avatar", params: { theme: "dark" }

    expect(response.body).not_to include("prefers-color-scheme")
    expect(response.body).to include(Assistant::AvatarsController::DARK[:disc])
  end

  it "asks for the dark picture on behalf of a user whose theme is dark" do
    user = build_stubbed(:user)
    user.pref.theme = "dark"

    expect(Assistant::AvatarsController.theme_of(user)).to eq("dark")
  end
end
