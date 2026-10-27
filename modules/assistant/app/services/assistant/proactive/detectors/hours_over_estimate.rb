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
      # Logged time on an open work package has passed 1.5 times its estimate
      # (03 §3.1, 04 C1). The person responsible is asked once per crossing:
      # change the estimate, or say what blocks it.
      class HoursOverEstimate < Base
        RATIO_PERCENT = 150

        def candidates
          estimated = open_work_packages.select { it.estimated_hours.to_f.positive? }
          logged = TimeEntry.where(entity_type: "WorkPackage", entity_id: estimated.map(&:id)).group(:entity_id).sum(:hours)
          estimated.filter_map do |wp|
            hours = logged[wp.id].to_f
            ratio = hours / wp.estimated_hours
            next if ratio < RATIO_PERCENT.fdiv(100)

            owner = Routing.owner_of(wp) or next
            build(wp, owner, hours.round(1), ratio)
          end
        end

        private

        def build(wp, owner, hours, ratio)
          left = Assistant::Facts.remaining_hours(wp) if wp.remaining_hours
          candidate(
            fingerprint: "#{wp.id}:#{wp.estimated_hours}:#{ratio.floor}", recipient: owner, subject: wp,
            nature: owner.id == wp.assigned_to_id ? :own : :object,
            headline: t("headline", ref: "##{wp.id}", hours:, estimate: wp.estimated_hours.round(1)),
            because: [t("ratio", percent: (ratio * 100).round),
                      (t("left", hours: left.round(1)) if left),
                      *people(wp)].compact,
            impact: { critical_path: graph.slack(wp.id)&.<=(0) || false, cascade: graph.downstream(wp.id).size },
            facts: { logged_hours: hours, estimated_hours: wp.estimated_hours, ratio: ratio.round(2) },
            steps_for: ->(_user) { options(wp, hours, left) }
          )
        end

        def people(wp)
          by_user = TimeEntry.where(entity: wp).group(:user_id).sum(:hours).sort_by { -it.last }.first(3)
          names = by_user.filter_map { |id, h| User.find_by(id:)&.then { "#{it.name} #{h.to_f.round(1)} h" } }
          names.any? ? [t("who", list: names.join(t("separator")))] : []
        end

        def options(wp, hours, left)
          estimate = (hours + (left || 0)).ceil
          [option(t("adjust", hours: estimate), t("adjust_consequence"), "adjust_estimate",
                  [step(wp, { "estimated_hours" => estimate })]),
           option(t("blocked"), t("blocked_consequence"), "blocked",
                  [comment(wp, t("blocked_comment", who: leads.first ? mention(leads.first) : ""))])]
        end
      end
    end
  end
end
