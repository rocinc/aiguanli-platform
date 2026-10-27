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
  # Answers the frame beside a version's date field with the line for the date
  # being typed, or an empty frame when nothing follows from it.
  class VersionAsidesController < ApplicationController
    before_action :find_version
    authorization_checked! :show

    FRAME_ID = "assistant-version-aside-frame"

    def show
      signal = Assistant::VersionDateAside.for(version: @version, user: current_user, effective_date: params[:effective_date])
      inner = signal ? aside_html(signal) : ""
      render html: helpers.turbo_frame_tag(FRAME_ID) { inner }
    end

    private

    def aside_html(signal)
      notice = Assistant::NoticeComponent.new(signal:, user: current_user, density: :line, heading_level: 2)
      helpers.content_tag(:div, render_to_string(notice, layout: false), class: "assistant-wp-aside")
    end

    def find_version
      @version = Version.visible(current_user).find_by(id: params[:version_id])
      head(:no_content) unless @version
    end
  end
end
