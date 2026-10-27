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
  class Usage < ApplicationRecord
    belongs_to :project, optional: true
    belongs_to :user, optional: true

    scope :this_month, -> { where(created_at: Time.current.beginning_of_month..) }

    def self.tokens = sum("prompt_tokens + completion_tokens")

    def self.over_budget?(project: nil) = reached?(1.0, project)

    def self.near_budget?(project: nil) = reached?(0.85, project)

    def self.reached?(share, project)
      globally = Setting.assistant_monthly_token_budget.to_i
      return true if globally.positive? && this_month.tokens >= globally * share

      cap = Assistant::Proactive::ProjectSettings.for(project).token_cap
      cap.positive? && this_month.where(project:).tokens >= cap * share
    end
    private_class_method :reached?
  end
end
