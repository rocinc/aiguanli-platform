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
  module Reasoning
    module Tools
      class CriticalPath < Base
        define "critical_path",
               "The chain of open work that decides when a version finishes, the slack of each link, and whether " \
               "the version date holds.",
               { version: { type: "string", description: "Version name or id; empty = next open version" } }

        def call(args)
          version = context.version(args["version"])
          graph = Assistant::Facts::ScheduleGraph.new(version.project)
          chain = graph.critical_chain(version)
          readiness = Assistant::Facts::VersionReadiness.new(version)
          {
            "version" => version.name, "date" => iso(version.effective_date),
            "chain" => chain.map do |node|
              { "id" => node.id, "subject" => node.subject, "start" => iso(node.start_date), "due" => iso(node.due_date),
                "assignee" => User.find_by(id: node.assignee_id)&.name, "slack_working_days" => graph.slack(node.id) }
            end,
            "slip_working_days" => readiness.slip_days, "because" => readiness.because
          }
        end
      end
    end
  end
end
