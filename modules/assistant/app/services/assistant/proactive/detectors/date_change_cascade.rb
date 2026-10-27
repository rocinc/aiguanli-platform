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
      # Someone moved a date and the platform moved others with it, or a version
      # now finishes late. The person who did it sees, on that work package,
      # what moved and what slipped, with a way to take it back. (The same
      # facts are available while editing: Assistant::Proactive::Inline.)
      class DateChangeCascade < Base
        def candidates
          events("work_package.updated").select { it.changed?("due_date") || it.changed?("start_date") }.filter_map do |event|
            wp = event.subject
            actor = event.actor
            next unless wp.is_a?(WorkPackage) && actor.is_a?(User) && event.journal

            next if aside_shown?(event, wp) || moved_by_host?(event)

            moved = moved_with(event)
            late = late_versions(wp)
            next if moved.empty? && late.empty?

            candidate(
              fingerprint: "#{event.journal_id}", recipient: actor, subject: wp, nature: :decision, channel: "inline",
              headline: t("headline", ref: "##{wp.id}", count: moved.size),
              because: [(t("moved", list: moved.first(6).map { "##{it.id}" }.join("、")) if moved.any?),
                        *late.map { t("late", version: it[:name], finish: day(it[:finish]), date: day(it[:date])) }].compact,
              impact: { cascade: moved.size, critical_path: late.any? },
              facts: { journal_id: event.journal_id },
              steps_for: lambda do |_user|
                before = { "start_date" => event.before("start_date"), "due_date" => event.before("due_date") }.compact
                before.any? ? [option(t("revert"), t("revert_consequence"), "revert_date", [step(wp, before)])] : []
              end
            )
          end
        end

        private

        def moved_by_host?(event) = event.journal.cause.to_h["type"].to_s.start_with?("work_package_related")

        def aside_shown?(event, wp)
          Assistant::Signal.exists?(recipient: event.actor, detector: Assistant::DateAside::DETECTOR,
                                    fingerprint: Assistant::DateAside.fingerprint(wp), created_at: (event.created_at - 1.hour)..)
        end

        def moved_with(event)
          Journal.where(journable_type: "WorkPackage").where("cause->>'work_package_id' = ?", event.subject_id.to_s)
                 .where(created_at: (event.created_at - 1.minute)..(event.created_at + 5.minutes))
                 .where.not(journable_id: event.subject_id).filter_map(&:journable).uniq
        end

        def late_versions(wp)
          wp.target_versions.filter_map do |version|
            finish = Assistant::Facts.work_packages_in(version).maximum(:due_date)
            if version.effective_date && finish && finish > version.effective_date
              { name: version.name, finish:,
                date: version.effective_date }
            end
          end
        end
      end
    end
  end
end
