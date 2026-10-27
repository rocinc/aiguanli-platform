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

module Assistant
  # The assistant's picture: a ✦ in a circle, drawn here so no page loads an
  # image from anywhere else.
  class AvatarsController < ApplicationController
    SHAPE = '<path class="s" d="M32 12c1.6 11 8.9 18.4 20 20-11.1 1.6-18.4 9-20 20-1.6-11-8.9-18.4-20-20 11.1-1.6 18.4-9 20-20z"/>'
    LIGHT = { disc: "#0969da", star: "#fff" }.freeze
    DARK = { disc: "#4493f8", star: "#0d1117" }.freeze

    # The theme is the user's setting inside the application, which the browser cannot see; without it the
    # picture follows the system preference.
    def self.theme_of(user)
      pref = user.pref
      return "dark" if pref.dark_color_mode?

      "light" if pref.light_color_mode?
    end

    def self.path_for(user)
      theme = theme_of(user)
      theme ? "/assistant/avatar?theme=#{theme}" : "/assistant/avatar"
    end

    def self.svg(theme)
      colors = theme == "dark" ? DARK : LIGHT
      following = theme.nil? ? "@media (prefers-color-scheme: dark) { .d { fill: #{DARK[:disc]} } .s { fill: #{DARK[:star]} } }" : ""
      <<~SVG.squish
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><style>.d { fill: #{colors[:disc]} } .s { fill: #{colors[:star]} } #{following}</style>
        <circle class="d" cx="32" cy="32" r="32"/>#{SHAPE}</svg>
      SVG
    end

    no_authorization_required! :show
    skip_before_action :check_if_login_required

    def show
      expires_in 1.day, public: true
      render body: self.class.svg(params[:theme].presence_in(%w[light dark])), content_type: "image/svg+xml"
    end
  end
end
