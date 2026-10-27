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
  # What people said, as one person may read it. Visibility is applied here
  # once, so nothing else decides on its own who may see an intent.
  class Said
    GRACE_WORKING_DAYS = 1
    COMMON_SHARE = 0.3
    RELATED_SHARE = 0.5

    def initialize(user, today: Date.current)
      @user = user
      @today = today
    end

    attr_reader :user, :today

    def visible = Intent.visible(user)

    def on_subject(subject)
      visible.on_subject(subject).where.not(status: "dismissed").includes(:owner, :counterparty).order(:stated_at)
    end

    def mine
      visible.live.where(owner_id: user.id, kind: %w[commitment deferral])
             .where.not(strength: %w[trivial requested]).includes(:subject, :counterparty)
             .order(Arel.sql("said_due_on ASC NULLS LAST"), :stated_at)
    end

    def requests_for_me
      visible.live.where(owner_id: user.id, kind: "commitment", strength: "requested")
             .includes(:subject, :counterparty).order(:stated_at)
    end

    def owed_to_me
      visible.live.where(counterparty_id: user.id, kind: %w[commitment deferral])
             .where.not(strength: %w[trivial requested])
             .where("assistant_intents.said_due_on IS NULL OR assistant_intents.said_due_on >= ? OR assistant_intents.said_due_on < ?",
                    today, grace_cutoff)
             .includes(:subject, :owner).order(Arel.sql("said_due_on ASC NULLS LAST"), :stated_at)
    end

    def questions_for_me
      visible.where(kind: "question", status: "open")
             .where(counterparty_id: user.id).includes(:subject, :owner).order(:stated_at)
    end

    def decisions(project) = visible.where(project:, kind: "decision")

    def related_decisions(project, text, limit: 3)
      wanted = Text.terms(text)
      return Intent.none if wanted.empty?

      said = visible.where(project:).where.not(status: "dismissed").pluck(:id, :kind, :status, :title, :quote, :stated_at)
      documents = said.to_h { |id, _, _, title, quote, _| [id, Text.terms("#{title} #{quote}")] }
      weights = term_weights(wanted, documents.values)
      total = weights.values.sum
      return Intent.none unless total.positive?

      ranked = said.filter_map do |id, kind, status, *, stated_at|
        next unless kind == "decision" && status == "active"

        share = (documents[id].to_a & weights.keys).sum { |term| weights[term] } / total
        [share, stated_at, id] if share >= RELATED_SHARE
      end
      ids = ranked.sort_by { |share, stated_at, _| [-share, -stated_at.to_i] }.first(limit).map(&:last)

      Intent.where(id: ids).includes(:owner).in_order_of(:id, ids)
    end

    def previous_meeting(meeting)
      scope = Meeting.where(project: meeting.project).where(start_time: ...meeting.start_time).order(start_time: :desc)
      scope = scope.where(recurring_meeting_id: meeting.recurring_meeting_id) if meeting.recurring_meeting_id
      scope.first
    end

    private

    def term_weights(terms, documents)
      ceiling = [documents.size * COMMON_SHARE, 1].max
      terms.each_with_object({}) do |term, weights|
        used = documents.count { |doc| doc.include?(term) }
        next if used.zero?

        weights[term] = used > ceiling ? 0.0 : Math.log((documents.size + 1).fdiv(used))
      end
    end

    def grace_cutoff
      date = today
      remaining = GRACE_WORKING_DAYS
      while remaining.positive?
        date -= 1
        remaining -= 1 if Setting.working_days.include?(date.cwday) && !NonWorkingDay.exists?(date:)
      end
      date
    end
  end
end
