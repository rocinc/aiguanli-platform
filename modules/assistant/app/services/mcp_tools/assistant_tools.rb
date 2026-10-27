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

module McpTools
  # Named constants for each wrapped reasoning tool, so the platform's registry
  # and its admin page list them by a stable name.
  module AssistantTools
    Assistant::Reasoning::Tools.all.each do |tool|
      const_set(AssistantTool.constant_for(tool), AssistantTool.for(tool))
    end
  end
end
