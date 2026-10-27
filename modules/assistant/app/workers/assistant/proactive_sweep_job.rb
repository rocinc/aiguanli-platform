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

module Assistant
  # Runs every detector over the projects where the assistant is enabled and
  # turns what passes the value gate into signals.
  class ProactiveSweepJob < ApplicationJob
    queue_with_priority :low

    include GoodJob::ActiveJobExtensions::Concurrency

    good_job_control_concurrency_with(total_limit: 1, key: -> { self.class.name })

    def perform
      Project.active.has_module(:assistant).find_each do |project|
        Assistant::Proactive::Engine.new(project).sweep
      rescue StandardError => e
        Rails.logger.error("[assistant] sweep failed for #{project.identifier}: #{e.class} #{e.message}")
      end
    end
  end
end
