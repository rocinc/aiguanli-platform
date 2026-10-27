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
  # One thing the assistant noticed for one person, and what became of it.
  class Signal < ApplicationRecord
    self.table_name = "assistant_signals"

    STATES = %w[pending held delivered dismissed expired].freeze
    CHANNELS = %w[inline brief notification comment].freeze
    # "rejected" is only "leave it" and declining the offered change. A
    # person's reasons for "this is wrong" and taking back what was done each
    # have an outcome of their own, so the learning loop can tell them apart.
    OUTCOMES = %w[adopted edited rejected snoozed muted ignored resolved wrong known not_mine undone].freeze
    GOOD_OUTCOMES = %w[adopted edited resolved].freeze
    STALE_LINGERS = 24.hours

    belongs_to :project, optional: true
    belongs_to :recipient, class_name: "User"
    belongs_to :subject, polymorphic: true, optional: true
    belongs_to :action, class_name: "Assistant::Action", optional: true

    validates :state, inclusion: { in: STATES }
    validates :channel, inclusion: { in: CHANNELS }
    validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true

    scope :live, -> { where(state: %w[pending held delivered], outcome: nil) }
    scope :for_brief, -> { live.where(channel: %w[brief notification]) }
    scope :inline_on, ->(subject) { live.where(subject:) }
    scope :offering, ->(action) {
      where(action_id: action.id).or(where("payload -> 'options' @> ?", [{ action_id: action.id }].to_json))
    }
    scope :cold_start_pool, -> { where(state: "held", outcome: nil).where("payload @> ?", { gate: ["cold_start"] }.to_json) }
    scope :judged, -> { where.not(outcome: [nil, "not_mine"]) }
    scope :recently_stale, -> { where(outcome: "resolved").where(outcome_at: STALE_LINGERS.ago..) }
    scope :interruptions_today, ->(user) {
      where(recipient: user, channel: "notification", delivered_at: Time.current.in_time_zone(user.time_zone).beginning_of_day..)
    }

    class << self
      def silenced?(detector, recipient:, project: nil)
        Assistant::Preference.effective(recipient, project).muted?(detector)
      end

      def offer!(**attributes)
        return if silenced?(attributes[:detector], recipient: attributes[:recipient], project: attributes[:project])

        create!(**attributes)
      end
    end

    def detector_class =Assistant::Proactive::Detectors.fetch(detector)

    def headline = payload["headline"]

    def because = Array(payload["because"])

    def why_me = Assistant::Notice::Why.new(self, recipient).sentence

    def options = Array(payload["options"])

    def settle!(outcome, **notes)
      update!(outcome:, outcome_at: Time.current, state: outcome == "snoozed" ? "held" : "dismissed",
              payload: payload.merge(notes.stringify_keys.compact))
    end

    def likely? = payload["certainty"] == "likely"

    def stale? = outcome == "resolved"

    def reply = payload["reply"]
  end
end
