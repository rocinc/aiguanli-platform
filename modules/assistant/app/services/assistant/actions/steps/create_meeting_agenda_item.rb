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
  module Actions
    module Steps
      # Adds an item to a meeting's agenda, the way a participant would. The
      # host puts it into the last section; with a work package it becomes a
      # work package item.
      class CreateMeetingAgendaItem < Base
        def project = meeting&.project

        def call(user:, cause:)
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless meeting

          work_package_id = attributes["work_package_id"].presence
          call = ::MeetingAgendaItems::CreateService.new(user:).call(
            meeting_id: meeting.id, title: attributes["title"], notes: attributes["notes"],
            presenter_id: attributes["presenter_id"].presence, duration_in_minutes: attributes["duration_in_minutes"].presence,
            work_package_id:,
            item_type: MeetingAgendaItem::ITEM_TYPES[work_package_id ? :work_package : :simple]
          )
          keep_decisions_last(call.result) if call.success?
          created_outcome(call)
        end

        private

        def keep_decisions_last(created)
          title = I18n.t("assistant.proactive.sprint_planning_prep.sections.decisions")
          return if created.title == title

          created.meeting.agenda_items.reload.find { it.title == title }&.move_to_bottom
        end

        def meeting = @meeting ||= Meeting.find_by(id: attributes["meeting_id"])
      end
    end
  end
end
