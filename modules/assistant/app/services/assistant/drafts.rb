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
  # Words written for a person to send (L2): an action whose steps only put
  # text or hours somewhere, waiting for the person who would sign it. Offered
  # as the single option of a signal, or lying around on its own for a while.
  class Drafts
    WORD_OPS = %w[comment create_forum_reply create_news_comment create_wiki_page publish_news update_project_status
                  create_meeting_outcome create_time_entry send_mail].freeze
    STANDALONE_WINDOW = 7.days
    NEVER_OFFERED = <<~SQL.squish
      NOT EXISTS (SELECT 1 FROM assistant_signals s WHERE s.action_id = assistant_actions.id
        OR s.payload -> 'options' @> jsonb_build_array(jsonb_build_object('action_id', assistant_actions.id)))
    SQL

    Item = Data.define(:action, :signal) do
      def score = signal&.score.to_i

      def at = signal&.created_at || action.created_at
    end

    def self.draft?(action, user)
      action.proposed? && action.steps.any? && action.steps.all? { WORD_OPS.include?(it["op"].to_s) } &&
        action.options.none? { it.is_a?(Hash) && it["key"].present? } && action.decidable_by?(user) &&
        action.steps.all? { Target.for(it, user) }
    end

    def initialize(user:, signals:, project: nil, now: Time.current)
      @user = user
      @signals = signals
      @project = project
      @now = now
    end

    # Signals whose only way forward is a draft are shown as that draft.
    def items
      @items ||= (offered + standalone).sort_by { [-it.score, -it.at.to_i, it.action.id] }
    end

    def signal_ids = items.filter_map { it.signal&.id }

    private

    attr_reader :user, :signals, :project

    def offered
      by_id = Assistant::Action.where(id: signals.flat_map { action_ids(it) }.uniq).index_by(&:id)
      signals.filter_map do |signal|
        ids = action_ids(signal)
        action = ids.one? ? by_id[ids.first] : nil
        Item.new(action:, signal:) if action && self.class.draft?(action, user)
      end
    end

    def action_ids(signal)
      ids = signal.options.filter_map { it["action_id"] if it.is_a?(Hash) }
      ids = [signal.action_id] if ids.empty? && signal.action_id
      ids
    end

    def standalone
      scope = Assistant::Action.proposed.where(on_behalf_of: user, created_at: (@now - STANDALONE_WINDOW)..).where(NEVER_OFFERED)
      scope = scope.where(project:) if project
      scope.includes(:project).select { self.class.draft?(it, user) }.map { Item.new(action: it, signal: nil) }
    end
  end
end
