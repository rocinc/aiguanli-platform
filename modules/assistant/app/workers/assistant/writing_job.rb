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
  class WritingJob < ApplicationJob
    queue_with_priority :above_normal

    def perform(run_id, project_id = nil)
      run = AI::TextTransformRun.find_by(id: run_id) or return
      Assistant::Writing.new(run, project: project_id && Project.find_by(id: project_id)).call
    end
  end
end
