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
  module Understanding
    # What the assistant wrote itself is not read back as something a person
    # said: an agenda item it created from a remembered promise carries the
    # words and the link of its source, and a reminder it drafted repeats what
    # was asked. Only what people add on top is read.
    module OwnWords
      module_function

      def journal?(journal)
        return false unless journal.cause_type == "assistant_action"

        Assistant::Action.where(id: journal.cause.to_h["action_id"]).where("plan ? 'intent'").exists?
      end

      def agenda_title(agenda_item)
        generated = generated_attributes(agenda_item)
        agenda_item.title.to_s.strip == generated["title"].to_s.strip ? nil : agenda_item.title
      end

      def agenda_notes(agenda_item)
        generated = generated_attributes(agenda_item)["notes"]
        return agenda_item.notes if generated.blank?

        written = generated.lines.map(&:strip).compact_blank.to_set
        agenda_item.notes.to_s.lines.reject { written.include?(it.strip) }.join
      end

      def generated_attributes(agenda_item)
        action = Assistant::Action.executed.where("inverse @> ?", [{ type: "MeetingAgendaItem", id: agenda_item.id }].to_json)
                                  .order(:executed_at).first
        step = action&.steps&.detect { it["op"] == "create_meeting_agenda_item" }
        step.to_h.fetch("attributes", {})
      end
    end
  end
end
