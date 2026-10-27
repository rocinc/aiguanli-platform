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
  # A change the assistant proposes or makes. It always says on whose behalf,
  # on what basis, what it did to which journals and how to take it back.
  class Action < ApplicationRecord
    STATUSES = %w[proposed executed rejected undone failed superseded].freeze
    TIERS = %w[t0 t1 t2 t3].freeze
    UNDO_WINDOW = 7.days

    belongs_to :project, optional: true
    belongs_to :subject, polymorphic: true, optional: true
    belongs_to :on_behalf_of, class_name: "User", optional: true
    belongs_to :decided_by, class_name: "User", optional: true
    belongs_to :undone_by, class_name: "User", optional: true
    has_many :signals, class_name: "Assistant::Signal", dependent: :nullify

    validates :status, inclusion: { in: STATUSES }
    validates :tier, inclusion: { in: TIERS }
    validates :kind, :title, presence: true

    scope :proposed, -> { where(status: "proposed") }
    scope :executed, -> { where(status: "executed") }
    scope :recent, -> { order(created_at: :desc) }

    def proposed? = status == "proposed"

    def executed? = status == "executed"

    def undone? = status == "undone"

    def needs_confirmation? = tier.in?(%w[t2 t3])

    def undoable? = executed? && inverse.present?

    def undo_needs_preview? = executed_at.present? && executed_at < UNDO_WINDOW.ago

    # Steps as stored in the plan: [{ "op" => "update", "type" => "WorkPackage", "id" => 1, "attributes" => {...} }]
    def steps = Array(plan["steps"])

    def options = Array(plan["options"])

    def basis_entries = Array(basis).map { Assistant::Basis.from_h(it) }

    def affected_users
      User.where(id: Array(preview["affected_user_ids"]))
    end

    def visible_to?(user)
      return on_behalf_of_id == user.id if private_proposal?
      return true if user.admin?
      return false if project && !user.allowed_in_project?(:use_assistant, project)

      on_behalf_of_id == user.id || user.allowed_in_project?(:view_work_packages, project)
    end

    def decidable_by?(user)
      return false unless proposed? && visible_to?(user)
      return user.admin? if project.nil?

      Assistant::Actions::Authority.new(self, user).may_decide?
    end

    def private_proposal? = proposed? && on_behalf_of_id.present?
  end
end
