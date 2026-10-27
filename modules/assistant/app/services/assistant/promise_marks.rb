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
  # Who has said they would do this work package, as a fact on the page
  # (S5.3). Only the person who said it and the person waiting for it are
  # shown it; everyone else sees the due date and nothing more, so a promise
  # never becomes a public score (N2). Nothing is counted or ranked.
  class PromiseMarks
    LIMIT = 3

    Mark = Data.define(:intent, :speaker, :person, :day, :said, :kind)

    def self.for(object, user) = new(object, user).marks

    def initialize(object, user)
      @object = object
      @user = user
    end

    attr_reader :object, :user

    def marks
      @marks ||= applicable? ? promises.filter_map { build(it) }.first(LIMIT) : []
    end

    private

    def applicable?
      object.is_a?(WorkPackage) && user&.logged? && Assistant::Surface.available?(object.project, user)
    end

    def promises
      Assistant::Said.new(user).on_subject(object).live.where(kind: %w[commitment deferral], strength: %w[firm tentative])
                     .where("assistant_intents.owner_id = :id OR assistant_intents.counterparty_id = :id", id: user.id)
                     .reorder(stated_at: :desc)
    end

    def build(promise)
      return unless promise.owner && Assistant::Marks.visible_source?(promise.source, user)

      yours = promise.owner == user
      speaker = yours ? I18n.t("assistant.marks.you") : promise.owner.name
      Mark.new(intent: promise, speaker:, person: (promise.owner unless yours), day: Assistant::Text.day(promise.stated_at.to_date), said: promise.said_due_expression.presence,
               kind: promise.kind)
    end
  end
end
