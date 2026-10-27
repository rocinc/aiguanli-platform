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
      # Member performance with evidence and fairness corrections. Allowed for
      # one's own profile, or with the "view member performance" permission;
      # every look at someone else is recorded and visible to them.
      class AppraiseTool < Base
        define "appraise",
               "Performance of one member or of the whole team over a period: delivery (on-time rate, corrected " \
               "for blocked time), estimation, output, quality, collaboration, keeping their word, knowledge, load " \
               "and situation. Each with team median, basis and the member's own notes. Use for \"who is slowest\", " \
               "\"evaluate Ben\", \"who fits X better\".",
               { person: { type: "string", description: "Member; empty with team=true for everyone" },
                 team: { type: "boolean" },
                 from: { type: "string", description: "YYYY-MM-DD, default 90 days ago" },
                 to: { type: "string" } }

        def call(args)
          from = context.date(args["from"], default: Date.current - 90)
          to = context.date(args["to"], default: Date.current)
          people = args["team"] && args["person"].blank? ? context.members : [context.person(args["person"])]
          people.each { authorize!(it) }

          team = Assistant::Appraisals::Team.new(project:, from:, to:)
          profiles = people.map { team.profile(it, viewer: user) }
          profiles.each(&:record_view!)
          { "period" => { "from" => iso(from), "to" => iso(to) }, "profiles" => profiles.map(&:to_h),
            "ranking" => people.size > 1 ? team.ranking : nil }.compact
        end

        private

        def authorize!(person)
          return if person == user
          return if user.allowed_in_project?(:view_member_performance, project)

          raise Refused, I18n.t("assistant.reasoning.errors.appraisal_not_allowed")
        end
      end
    end
  end
end
