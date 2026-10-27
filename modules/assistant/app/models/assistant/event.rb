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
  # One row per thing that happened in a project, in a single shape, so that
  # detectors can be replayed and new rules can be run over the past.
  class Event < ApplicationRecord
    belongs_to :subject, polymorphic: true
    belongs_to :project, optional: true
    belongs_to :actor, class_name: "User", optional: true
    belongs_to :journal, optional: true

    scope :unprocessed, -> { where(processed_at: nil) }
    scope :by_humans, -> { where.not(actor_id: AssistantUser.select(:id)) }

    def changed?(attribute) = changes_made.key?(attribute.to_s)

    def before(attribute) = changes_made.dig(attribute.to_s, 0)

    def after(attribute) = changes_made.dig(attribute.to_s, 1)
  end
end
