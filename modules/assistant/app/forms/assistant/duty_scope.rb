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
  # What each kind of duty can be told, as the handlers read it from
  # `duty.scope`. Anything else in the request is dropped.
  module DutyScope
    module_function

    FIELDS = {
      "weekly_status" => %w[wday hour],
      "release_watch" => %w[version_id external_to],
      "decision_log" => %w[title ceiling],
      "advance_merged_pr" => %w[status_id ceiling]
    }.freeze

    def fields(kind) = FIELDS.fetch(kind.to_s, [])

    def permit(kind, raw, project: nil)
      given = raw.respond_to?(:permit) ? raw.permit(*fields(kind)).to_h : raw.to_h.slice(*fields(kind))
      cleaned = given.to_h { |key, value| [key.to_s, clean(key.to_s, value)] }.compact_blank
      project ? cleaned.select { |key, value| offered?(project, key, value) } : cleaned
    end

    def offered?(project, key, value)
      case key
      when "version_id" then project.shared_versions.exists?(id: value)
      when "status_id" then Status.exists?(id: value)
      when "title" then project.wiki&.pages&.exists?(title: value) || false
      else true
      end
    end

    def addresses(value)
      value.to_s.split(/[\s,;]+/).grep(URI::MailTo::EMAIL_REGEXP).uniq.first(10).join(", ")
    end

    def ceiling(duty) = duty.scope.to_h["ceiling"] == "draft" ? "draft" : "direct"

    def clean(key, value)
      case key
      when "wday" then value.to_i.clamp(1, 5).to_s
      when "hour" then value.to_i.clamp(0, 23).to_s
      when "version_id", "status_id" then value.to_s[/\A\d+\z/]
      when "ceiling" then value.to_s if value.to_s == "draft"
      when "external_to" then addresses(value)
      else value.to_s.strip.first(120)
      end
    end
  end
end
