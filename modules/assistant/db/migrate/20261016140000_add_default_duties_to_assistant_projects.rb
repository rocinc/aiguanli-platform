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

class AddDefaultDutiesToAssistantProjects < ActiveRecord::Migration[8.0]
  def up
    EnabledModule.where(name: "assistant").includes(:project).find_each do |enabled|
      project = enabled.project or next
      delegator = Assistant::Duty.where(project:).order(:created_at).first&.delegator ||
                  Assistant::Proactive::Routing.leads(project).first
      next unless delegator

      Assistant::Duties::Defaults.ensure!(project, delegator)
    end
  end

  def down; end
end
