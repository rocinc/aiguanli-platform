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
  module Proactive
    module Detectors
      # The first thing a team sees of the assistant (06 M1): one line on the
      # project overview, for each member who was in the project when it was
      # switched on (except whoever did it), and only for the first two weeks. Whoever joins later is
      # greeted by the onboarding duty instead.
      class AssistantArrival < Base
        SHOWN_FOR = 14.days
        QUIET_WORKING_DAYS = 10

        def candidates
          joined = Member.find_by(project:, principal: Assistant.user)&.created_at
          return [] unless joined && joined.to_date >= today - SHOWN_FOR

          quiet_until = Assistant::Facts.add_working_days(joined.to_date, QUIET_WORKING_DAYS)
          present = Member.where(project:, principal: Routing.people(project)).where(created_at: ..(joined + 1.day))
                          .includes(:principal).map(&:principal)
          (present - [enabler]).map { build(it, joined, quiet_until) }
        end

        private

        def build(person, joined, quiet_until)
          candidate(
            fingerprint: "arrival:#{project.id}", recipient: person, subject: project, nature: :intro, channel: "inline",
            headline: t("headline", added: added(joined)),
            because: [t("does"), t("does_not"), t("quiet", date: day(quiet_until))],
            impact: { people: 1 }, facts: { why: "member" }
          )
        end

        def enabler = @enabler ||= Assistant::Duty.where(project:).order(:created_at, :id).first&.delegator

        def added(joined)
          who = enabler&.firstname || t("someone")
          joined.to_date == today ? t("added_today", who:) : t("added_on", who:, date: I18n.l(joined.to_date, format: "%-m/%-d"))
        end
      end
    end
  end
end
