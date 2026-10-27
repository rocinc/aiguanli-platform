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
      # Hands a change to the action layer for the asking person. T1 is done on
      # the spot; T2/T3 comes back as a card the person confirms.
      class ProposeTool < Base
        define "propose",
               "Make a change in the project for the asking person. It is previewed as them and tiered by code: " \
               "T1 is done immediately and can be undone, T2/T3 waits for their confirmation. Returns action_id.",
               { title: { type: "string", description: "One line naming the change, in the person's language" },
                 kind: { type: "string", description: "Short machine name, e.g. reschedule, reassign, comment, draft_wiki" },
                 steps: { type: "array", items: PreviewTool::STEP_SCHEMA },
                 quote: { type: "string", description: "The person's own words that asked for this, if any" },
                 hold: { type: "boolean",
                         description: "Only prepare it: it stays a card waiting for the person's confirmation even when it " \
                                      "would be T1. Use it when the person is only exploring options." } },
               required: %w[title steps]

        def call(args)
          steps = StepBuilder.new(context).call(args["steps"])
          action = self.class.propose(context, title: args["title"], kind: args["kind"].presence || "change", steps:,
                                               quote: args["quote"], auto_execute: !ActiveModel::Type::Boolean.new.cast(args["hold"]))
          self.class.summary(action)
        end

        def self.propose(context, title:, kind:, steps:, quote: nil, auto_execute: true, options: [])
          basis = context.basis.map { quote.present? ? it.with(quote:) : it }
          Assistant::Actions::Propose.call(kind:, title:, steps:, on_behalf_of: context.user, project: context.project,
                                           subject: context.subject.is_a?(ActiveRecord::Base) ? context.subject : nil,
                                           basis:, options:, auto_execute:)
        end

        def self.summary(action)
          preview = action.preview || {}
          { "action_id" => action.id, "status" => action.status, "tier" => action.tier, "title" => action.title,
            "done" => action.executed?, "needs_confirmation" => action.proposed?,
            "error" => action.error, "changes" => Array(preview["changes"]).first(10),
            "version_slips" => preview["version_slips"],
            "affected_people" => User.where(id: Array(preview["affected_user_ids"])).map(&:name),
            "cards" => [Cards.action(action)] }.compact
        end
      end
    end
  end
end
