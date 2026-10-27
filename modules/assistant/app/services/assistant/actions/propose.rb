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
  module Actions
    # The single way into the action layer: build the action, preview it as
    # the person it is for, decide the tier, and run it right away when it is
    # T1. Everything else waits for a person.
    class Propose
      def self.call(...) = new(...).call

      def initialize(kind:, title:, steps:, on_behalf_of:, project: nil, subject: nil, basis: [], options: [],
                     auto_execute: true, said: nil)
        basis = Array(basis).map { it.respond_to?(:to_h) ? it.to_h : it }
        steps = SourceNote.apply(steps.map(&:deep_stringify_keys), basis)
        @attributes = { kind:, title:, project:, subject:, on_behalf_of:, basis:,
                        plan: { "steps" => steps, "options" => options,
                                "said" => said&.deep_stringify_keys }.compact }
        @auto_execute = auto_execute
      end

      def call
        action = Action.new(@attributes.merge(status: "proposed", tier: "t2"))
        preview = Preview.new(steps: action.steps, user: action.on_behalf_of || Assistant.user).call
        action.preview = preview.to_h
        unless preview.success
          action.status = "failed"
          action.error = preview.errors.join("; ")
          action.tier = "t0"
          action.save!
          return action
        end

        action.tier = Tiering.lowered_by_grant(action, Tiering.call(action:, preview: action.preview))
        action.save!
        Execute.call(action, decided_by: nil) if @auto_execute && action.tier == "t1"
        action
      end
    end
  end
end
