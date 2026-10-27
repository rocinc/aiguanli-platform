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
  # What a person said that the assistant keeps: a promise, a deferral, a
  # decision, a question. A record of the words, not a ledger. When the
  # subject is a work package, its dates and state are read from the work
  # package; `said_due_on` is only the date the person named.
  class Intent < ApplicationRecord
    STATUSES_BY_KIND = {
      "commitment" => %w[open done withdrawn superseded dismissed],
      "deferral" => %w[open done withdrawn dismissed],
      "question" => %w[open answered dismissed],
      "decision" => %w[active superseded dismissed]
    }.freeze

    KINDS = STATUSES_BY_KIND.keys.freeze
    STRENGTHS = %w[firm tentative requested trivial].freeze
    LIVE_STATUSES = %w[open active].freeze
    SUBJECT_PERMISSIONS = { "Message" => :view_messages, "WikiPage" => :view_wiki_pages, "News" => :view_news }.freeze

    belongs_to :project
    belongs_to :owner, class_name: "User", optional: true
    belongs_to :counterparty, class_name: "User", optional: true
    belongs_to :source, polymorphic: true
    belongs_to :subject, polymorphic: true
    belongs_to :due_anchor, polymorphic: true, optional: true
    belongs_to :answered_by, polymorphic: true, optional: true
    belongs_to :work_package, optional: true
    belongs_to :supersedes, class_name: "Assistant::Intent", optional: true
    belongs_to :parent, class_name: "Assistant::Intent", optional: true

    validates :kind, inclusion: { in: KINDS }
    validates :strength, inclusion: { in: STRENGTHS }
    validates :title, :quote, :stated_at, :extractor_version, presence: true
    validate :status_belongs_to_kind

    scope :live, -> { where(status: LIVE_STATUSES) }
    scope :of_kind, ->(kind) { where(kind:) }
    scope :nudgeable, -> { live.where(kind: %w[commitment deferral], strength: "firm").where.not(owner_id: nil) }
    scope :on_subject, ->(subject) { where(subject:) }
    scope :objections, -> { where.not(parent_id: nil) }

    def self.visible(user = User.current)
      allowed = where(project_id: Project.allowed_to(user, :use_assistant).select(:id))
      internal_ok = Project.allowed_to(user, :view_internal_comments).select(:id)

      allowed
        .where(internal: false)
        .or(allowed.where(internal: true, project_id: internal_ok))
        .where(subject_visible(user))
    end

    def self.subject_visible(user)
      visible_ids = WorkPackage.visible(user).select(:id)
      table = arel_table
      condition = table[:subject_type].not_in(["WorkPackage", *SUBJECT_PERMISSIONS.keys])
                                      .or(table[:subject_type].eq("WorkPackage").and(table[:subject_id].in(visible_ids.arel)))
      SUBJECT_PERMISSIONS.each do |type, permission|
        allowed = Project.allowed_to(user, permission).select(:id)
        condition = condition.or(table[:subject_type].eq(type).and(table[:project_id].in(allowed.arel)))
      end
      condition
    end

    def live? = status.in?(LIVE_STATUSES)

    def commitment_like? = kind.in?(%w[commitment deferral])

    def overdue?(today = Date.current)
      live? && commitment_like? && said_due_on.present? && said_due_on < today
    end

    def due_today?(today = Date.current)
      live? && commitment_like? && said_due_on == today
    end

    def settle!(to)
      update!(status: to, resolved_at: Time.current)
    end

    def move_to!(date, expression = nil)
      update!(moves: said_due_on.present? ? moves + 1 : moves, said_due_on: date,
              said_due_expression: expression || said_due_expression, due_anchor: nil, status: "open", resolved_at: nil)
    end

    def reopen!
      update!(status: kind == "decision" ? "active" : "open", resolved_at: nil)
    end

    def raised_objections = self.class.where(parent_id: id, kind: "question")

    def open_objections = raised_objections.where(status: "open")

    def contested? = kind == "decision" && open_objections.exists?

    def anchor_label
      due_anchor.name if due_anchor.is_a?(Sprint) || due_anchor.is_a?(Version)
    end

    private

    def status_belongs_to_kind
      return if STATUSES_BY_KIND.fetch(kind, []).include?(status)

      errors.add(:status, :inclusion)
    end
  end
end
