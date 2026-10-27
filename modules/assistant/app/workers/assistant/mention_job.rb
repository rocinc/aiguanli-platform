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
  class MentionJob < ApplicationJob
    queue_with_priority :above_normal

    retry_on(Assistant::Llm::Error, wait: :polynomially_longer, attempts: 3) { |job, _| job.apologise(:unavailable) }
    discard_on(Assistant::Llm::NotConfigured) { |job, _| job.apologise(:not_configured) }
    discard_on(Assistant::Llm::OverBudget) { |job, _| job.apologise(:over_budget) }

    def perform(record, asker = nil, placeholder = nil)
      Assistant::Called::Mention.new(record, asker:, placeholder:).call
    end

    def apologise(reason)
      Assistant::Called::Mention.new(arguments.first, asker: arguments.second, placeholder: arguments.third).apologise(reason)
    end
  end
end
