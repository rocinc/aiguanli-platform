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
  class IntentVerbs
    # What a verb leaves behind on the remembered thing once its action has
    # happened: the new owner, the answer, the work package made for it. An
    # action that waits to be sent (a draft) has its effects when it goes out.
    module Effects
      module_function

      def reconcile(intent)
        Assistant::Action.executed.where("plan -> 'intent' ->> 'id' = ?", intent.id.to_s)
                         .where("plan -> 'intent' ->> 'applied' IS NULL").find_each { apply(intent, it) }
        intent.reload
      end

      def apply(intent, action)
        effects = action.plan.dig("intent", "effects").to_h
        attributes = effects.slice("owner_id", "counterparty_id")
        attributes["work_package_id"] = created_work_package(action) if effects["work_package"]
        intent.update!(attributes.compact)
        Assistant::Understanding::UnownedItems.settled(intent) if attributes["owner_id"]
        answer(intent, action, effects)
        action.update!(plan: action.plan.merge("intent" => action.plan["intent"].merge("applied" => true)))
      end

      def answer(intent, action, effects)
        record = answering_record(action) if effects["settle"] || effects["answered"]
        intent.update!(answered_by: record) if record
        intent.settle!(effects["settle"]) if effects["settle"] && intent.live?
      end

      def created_work_package(action)
        action.inverse.detect { it["type"] == "WorkPackage" && it["created"] }&.fetch("id")
      end

      def answering_record(action)
        created = action.inverse.detect { it["created"] && %w[MeetingOutcome Message].include?(it["type"]) }
        return created["type"].constantize.find_by(id: created["id"]) if created

        Journal.where(id: action.journal_ids).order(:id).last
      end
    end
  end
end
