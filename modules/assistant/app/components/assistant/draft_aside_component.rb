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
  # The frame a form reserves beside a field. The `assistant--draft-aside`
  # controller points it at `url` with the form's draft values whenever they
  # change, and empties it when they are back at what was saved.
  class DraftAsideComponent < ApplicationComponent
    def initialize(frame_id:, url:, fields:)
      super()
      @frame_id = frame_id
      @url = url
      @fields = fields
    end

    def call
      content_tag("turbo-frame", "", id: @frame_id, class: "hide-when-print",
                                     data: { controller: "assistant--draft-aside", "assistant--draft-aside-url-value": @url,
                                             "assistant--draft-aside-fields-value": @fields.to_json })
    end
  end
end
