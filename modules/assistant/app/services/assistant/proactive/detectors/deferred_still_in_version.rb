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

module Assistant
  module Proactive
    module Detectors
      # Someone said "next version" ("下版再做", a deferral anchored to the next
      # version) and the work package still sits on the version they deferred
      # it from (03 §3.1, 04 A4). Told to whoever said it, with the move ready.
      class DeferredStillInVersion < Base
        def candidates
          deferrals.filter_map do |item, wp, current, later|
            speaker = item.owner || item.source.try(:user)
            speaker = leads.first unless speaker.is_a?(User) && speaker.active? && !speaker.is_a?(AssistantUser)
            next unless speaker

            build(item, wp, current, later, speaker)
          end
        end

        private

        def deferrals
          Assistant::Intent.live.where(project:, kind: "deferral", subject_type: "WorkPackage", due_anchor_type: "Version")
                            .where(stated_at: 60.days.ago..).includes(:subject, :due_anchor, :source).filter_map do |item|
            wp = item.subject
            later = item.due_anchor
            next unless wp.is_a?(WorkPackage) && Assistant::Facts.open?(wp) && later.is_a?(Version)

            current = Assistant::Facts.version_of(wp)
            next unless current && current.id != later.id
            next if current.effective_date && later.effective_date && current.effective_date >= later.effective_date

            [item, wp, current, later]
          end
        end

        def build(item, wp, current, later, speaker)
          candidate(
            fingerprint: "#{item.id}:#{current.id}", recipient: speaker, subject: wp, nature: :decision,
            headline: t("headline", ref: "##{wp.id}", version: current.name),
            because: [t("said", quote: item.quote.truncate(60), date: day(item.stated_at.to_date), later: later.name),
                      t("still", ref: "##{wp.id}", version: current.name, date: day(current.effective_date))],
            impact: { deadline: current.effective_date.present?, people: 1 },
            act_by: current.effective_date, facts: { since: item.stated_at, item_id: item.id },
            steps_for: lambda do |_user|
              [option(t("move", version: later.name), t("move_consequence", version: current.name), "move_version",
                      [step(wp, { "version_id" => later.id })])]
            end
          )
        end
      end
    end
  end
end
