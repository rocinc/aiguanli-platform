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
  # Turns a preview (what would change, what moves along, which versions slip,
  # who is affected) into sentences a person reads in a few seconds.
  class PreviewPresenter
    Change = Data.define(:label, :url, :created, :cascaded, :attributes, :kind, :detail)
    Attribute = Data.define(:name, :before, :after, :type)
    Slip = Data.define(:name, :target, :before, :after, :newly_late, :still_late, :recovered)

    DATE_ATTRIBUTES = %w[start_date due_date].freeze
    USER_ATTRIBUTES = %w[assigned_to_id responsible_id user_id].freeze
    HIDDEN_ATTRIBUTES = %w[duration lock_version updated_at schedule_manually derived_start_date derived_due_date
                           ignore_non_working_days journal_cause].freeze

    def initialize(preview)
      @preview = preview.to_h.stringify_keys
    end

    attr_reader :preview

    def success? = preview.fetch("success", true)

    def errors = Array(preview["errors"])

    def changes
      @changes ||= Array(preview["changes"]).filter_map { build_change(it) }
    end

    def direct_changes = changes.reject(&:cascaded)

    def cascaded_changes = changes.select(&:cascaded)

    def slips
      @slips ||= Array(preview["version_slips"]).map do |slip|
        late = slip["late"].present?
        was_late = slip["was_late"].present?
        Slip.new(name: slip["name"], target: date(slip["target"]), before: date(slip["finish_before"]),
                 after: date(slip["finish_after"]), newly_late: late && !was_late, still_late: late && was_late,
                 recovered: !late && was_late)
      end
    end

    def newly_late_slips = slips.select(&:newly_late)

    def affected_users
      @affected_users ||= User.where(id: Array(preview["affected_user_ids"])).to_a
    end

    def notified_users
      @notified_users ||= User.where(id: Array(preview["notified_user_ids"]) - Array(preview["affected_user_ids"])).to_a
    end

    def empty? = changes.empty? && slips.empty?

    def headline_change = direct_changes.first || changes.first

    private

    def cascaded_gids = Array(preview["cascaded"])

    def build_change(hash)
      attributes = hash["changes"].to_h.except(*HIDDEN_ATTRIBUTES).map do |name, (before, after)|
        Attribute.new(name:, before: value(name, before, hash["type"]), after: value(name, after, hash["type"]),
                      type: hash["type"])
      end
      return if attributes.empty? && !hash["created"]

      Change.new(label: hash["label"].to_s, url: url_for(anchor_of(hash)), created: hash["created"].present?,
                 cascaded: cascaded_gids.include?(hash["gid"]), attributes:, kind: hash["kind"].to_s,
                 detail: hash["detail"].to_h)
    end

    def anchor_of(hash)
      return hash["anchor"] if hash.key?("anchor")

      hash if hash["type"] == "WorkPackage" && !hash["created"]
    end

    def url_for(anchor)
      return unless anchor&.dig("id")

      case anchor["type"]
      when "WorkPackage" then url_helpers.work_package_path(anchor["id"])
      when "Version" then url_helpers.version_path(anchor["id"])
      when "Project" then url_helpers.project_path(anchor["id"])
      when "Meeting" then url_helpers.meeting_path(anchor["id"])
      when "GithubPullRequest" then ::GithubPullRequest.find_by(id: anchor["id"])&.github_html_url
      end
    end

    def value(name, raw, _type)
      return if raw.nil? || raw == "" || raw == []
      return date(raw) if DATE_ATTRIBUTES.include?(name) || raw.to_s.match?(/\A\d{4}-\d\d-\d\d(T|\z)/)
      return User.find_by(id: raw)&.name if USER_ATTRIBUTES.include?(name)

      case name
      when "work_package_ids" then Array(raw).map { "##{it}" }.join(", ").presence
      when "status_code" then I18n.t("activerecord.attributes.project.status_codes.#{raw}", default: raw.to_s)
      when "status_id" then Status.find_by(id: raw)&.name
      when "priority_id" then IssuePriority.find_by(id: raw)&.name
      when "type_id" then ::Type.find_by(id: raw)&.name
      when "version_id" then Version.find_by(id: raw)&.name
      when "parent_id" then "##{raw}"
      when "estimated_hours", "remaining_hours", "hours" then I18n.t("assistant.card.hours", hours: raw)
      when "done_ratio" then "#{raw}%"
      else raw.to_s.truncate(60)
      end
    end

    def date(raw)
      return if raw.blank?

      Date.iso8601(raw.to_s[0, 10])
    rescue Date::Error
      nil
    end

    def url_helpers = OpenProject::StaticRouting::StaticUrlHelpers.new
  end
end
