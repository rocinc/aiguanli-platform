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
    # A project's own say over the rules, kept on its Assistant::Preference:
    #   muted_detectors                      rules switched off for everyone here
    #   thresholds["lead_ids"]               who leads (Routing.leads), when the roles do not say
    #   thresholds["role_levels"]            level by role id, for members who chose none themselves
    #   thresholds["duties"]                 the duty kinds the project allows (all when never set)
    #   thresholds["token_cap"]              this project's monthly token ceiling (none when 0)
    class ProjectSettings
      def self.for(project) = new(project && Assistant::Preference.find_by(owner: project))

      def initialize(preference)
        @preference = preference
      end

      def enabled?(detector) = !Array(@preference&.muted_detectors).include?(detector.to_s)

      def lead_ids = Array(thresholds["lead_ids"]).map(&:to_i).select(&:positive?)

      def duty_allowed?(kind) = !thresholds.key?("duties") || Array(thresholds["duties"]).include?(kind.to_s)

      def token_cap = thresholds["token_cap"].to_i.clamp(0..)

      # The project settings page writes through here; a rule that does not exist is dropped.
      def self.write!(project, enabled: nil, lead_ids: nil, level: :keep, role_levels: nil, duties: nil, token_cap: nil)
        preference = Assistant::Preference.for(project)
        preference.proactivity = level.presence_in(Assistant::Preference::LEVELS) unless level == :keep
        preference.role_levels = role_levels if role_levels
        preference.thresholds = preference.thresholds.merge(page_thresholds(lead_ids:, duties:, token_cap:))
        preference.muted_detectors = Catalog.keys - Array(enabled).map(&:to_s) if enabled
        preference.save!
        preference
      end

      def self.page_thresholds(lead_ids:, duties:, token_cap:)
        { "duties" => (Array(duties).map(&:to_s) & Assistant::Duty::KINDS if duties),
          "token_cap" => token_cap&.to_i&.clamp(0..),
          "lead_ids" => (Array(lead_ids).map(&:to_i).select(&:positive?).uniq if lead_ids) }.compact
      end

      private

      def thresholds = @preference&.thresholds || {}
    end
  end
end
