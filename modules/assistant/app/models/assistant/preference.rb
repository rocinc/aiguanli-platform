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
  # How a person or a project wants the assistant to behave.
  class Preference < ApplicationRecord
    LEVELS = %w[quiet standard active].freeze
    # Interruptions outside the brief, per person and day, by level. A number
    # the person chose themselves is theirs and goes above or below this;
    # the number the assistant adapts on its own never goes above it.
    CAPS = { "quiet" => 1, "standard" => 2, "active" => 4 }.freeze

    belongs_to :owner, polymorphic: true

    validates :proactivity, inclusion: { in: LEVELS }, allow_nil: true

    def self.for(owner) = find_or_initialize_by(owner:)

    def self.effective(user, project = nil)
      own = user && find_by(owner: user)
      team = project && find_by(owner: project)
      level = level_for(own, team, user, project)
      paused_until = own.paused_until if own&.paused?
      muted = Array(own&.muted_detectors) | Array(team&.muted_detectors) | own&.muted_in(project).to_a
      Effective.new(level:, cap: cap_for(own, level, paused_until), muted:, thresholds: own&.thresholds || {}, paused_until:)
    end

    def self.level_for(own, team, user = nil, project = nil)
      own&.project_level(project) || own&.proactivity || team&.role_level(user, project) || team&.proactivity ||
        Setting.assistant_default_proactivity.presence || "standard"
    end

    def self.cap_for(own, level, paused_until)
      return 0 if paused_until

      return own.interrupt_cap if own&.cap_chosen? && own.interrupt_cap

      ceiling = CAPS.fetch(level, 2)
      (own&.interrupt_cap || ceiling).clamp(0, ceiling)
    end

    Effective = Data.define(:level, :cap, :muted, :thresholds, :paused_until) do
      def quiet? = level == "quiet" || paused_until.present?

      def active? = level == "active"

      def muted?(detector) = muted.include?(detector.to_s)
    end

    def cap_chosen? = thresholds["cap_chosen"] == true

    def choose_cap(count)
      self.interrupt_cap = count
      self.thresholds = thresholds.merge("cap_chosen" => count.present?)
    end

    def project_levels = thresholds["project_levels"].to_h

    def project_levels=(levels)
      self.thresholds = thresholds.merge("project_levels" => levels.to_h.stringify_keys.select do |_, level|
        LEVELS.include?(level)
      end)
    end

    def project_level(project) = project && project_levels[project.id.to_s].presence_in(LEVELS)

    def role_levels = thresholds["role_levels"].to_h

    def role_levels=(levels)
      self.thresholds = thresholds.merge("role_levels" => levels.to_h.stringify_keys.select { |_, level| LEVELS.include?(level) })
    end

    # The quietest level set for any of the roles the person has in the project.
    def role_level(user, project)
      return if user.nil? || project.nil? || role_levels.empty?

      role_ids = Member.where(project:, principal: user).joins(:member_roles).pluck("member_roles.role_id")
      role_levels.values_at(*role_ids.map(&:to_s)).compact.min_by { LEVELS.index(it) }
    end

    # Kinds of thing the assistant does by itself that this person wants to be
    # asked about first (L5, M10), and those they have already been asked about.
    def asks_first?(kind) = Array(thresholds["ask_first"]).include?(kind.to_s)

    def asked_first?(kind) = Array(thresholds["asked_first"]).include?(kind.to_s)

    def ask_first!(kind) = update!(thresholds: thresholds.merge("ask_first" => Array(thresholds["ask_first"]) | [kind.to_s]))

    def asked_first!(kind) = update!(thresholds: thresholds.merge("asked_first" => Array(thresholds["asked_first"]) | [kind.to_s]))

    def paused?(now = Time.current) = paused_until.present? && paused_until > now

    def pause_until!(time) = update!(paused_until: time)

    def resume! = update!(paused_until: nil)

    def mute!(detector)
      update!(muted_detectors: (Array(muted_detectors) | [detector.to_s]))
    end

    def unmute!(detector)
      update!(muted_detectors: Array(muted_detectors) - [detector.to_s])
    end

    def mute_in!(detector, project)
      ids = Array(muted_in_projects[detector.to_s]) | [project.id]
      update!(muted_in_projects: muted_in_projects.merge(detector.to_s => ids))
    end

    def unmute_in!(detector, project)
      ids = Array(muted_in_projects[detector.to_s]) - [project.id]
      update!(muted_in_projects: muted_in_projects.except(detector.to_s).merge(ids.any? ? { detector.to_s => ids } : {}))
    end

    def muted_in(project)
      return [] unless project

      muted_in_projects.select { |_, ids| Array(ids).include?(project.id) }.keys
    end
  end
end
