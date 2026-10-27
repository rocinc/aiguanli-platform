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
  # The page beacon: "this person had this object in view". Only objects the
  # person may see are recorded; anything else is answered the same way, so
  # the endpoint tells nothing about what exists.
  class ViewsController < ApplicationController
    TYPES = { "work_package" => WorkPackage, "meeting" => Meeting, "message" => ::Message, "wiki_page" => WikiPage,
              "news" => News, "version" => Version, "project" => Project }.freeze

    before_action :require_login
    authorization_checked! :create

    def create
      type = TYPES[params[:type].to_s]
      record = type&.find_by(id: params[:id].to_i)
      if record&.visible?(current_user)
        Assistant::View.seen!(current_user, record)
        Assistant::Proactive::Feedback.seen!(Assistant::Signal.live.where(recipient: current_user, subject: record))
      end
      head :no_content
    end
  end
end
