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

# The assistant as a member of the team. It is a real user so that it can be
# assigned, mentioned, watched and invited like anyone else, but it does not
# count as a human seat and can never sign in.
class AssistantUser < User
  LOGIN = "ai-assistant"

  validate :only_one, on: :create

  def self.instance
    RequestStore[:assistant_user] ||= first || create_instance!
  end

  def self.create_instance!
    create!(login: LOGIN, firstname: "AI", lastname: I18n.t("assistant.identity.default_lastname"),
            mail: "ai-assistant@assistant.invalid", admin: false, status: User.statuses[:active],
            first_login: false, language: Setting.default_language)
  rescue ActiveRecord::RecordNotUnique
    first!
  end

  def self.rename!(name)
    first, *rest = name.to_s.strip.split(/\s+/, 2)
    instance.update_columns(firstname: rest.any? ? first : "", lastname: rest.first || first)
  end

  def assistant? = true

  def password_authentication? = false

  def check_password?(_) = false

  def available_custom_fields = []

  def time_zone
    ActiveSupport::TimeZone[Setting.user_default_timezone.presence || "Etc/UTC"]
  end

  private

  def only_one
    errors.add(:base, :taken) if self.class.exists?
  end
end
