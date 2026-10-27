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
  # What the assistant has for one person on one object right now: the
  # signals meant to be seen there and the proposals waiting for a decision.
  class Surface
    def self.available?(project, user)
      return false if project.nil? || user.nil? || !user.logged? || user.is_a?(AssistantUser)

      RequestStore.fetch([:assistant_available, project.id, user.id]) do
        project.module_enabled?(:assistant) && user.allowed_in_project?(:use_assistant, project)
      end
    end

    def initialize(subject:, user:)
      @subject = subject
      @user = user
    end

    attr_reader :subject, :user

    def project = subject.is_a?(Project) ? subject : subject.try(:project)

    def available? = self.class.available?(project, user)

    def signals
      @signals ||= Assistant::Signal.inline_on(subject).where(recipient: user)
                                    .where("snoozed_until IS NULL OR snoozed_until <= ?", Time.current)
                                    .includes(:action).order(score: :desc, created_at: :desc).to_a
    end

    def stale_signals
      @stale_signals ||= Assistant::Signal.recently_stale.where(subject:, recipient: user).includes(:action).order(outcome_at: :desc).to_a
    end

    # Proposals already offered by one of the signals are shown with it.
    def proposals
      @proposals ||= begin
        offered = signals.flat_map { |signal| [signal.action_id, *signal.options.filter_map { _1["action_id"] }] }.compact
        Assistant::Action.proposed.where(subject:).where.not(id: offered).includes(:on_behalf_of).recent.to_a
                         .select { _1.visible_to?(user) }
      end
    end

    def count = signals.size + proposals.count { _1.decidable_by?(user) }

    def empty? = signals.empty? && proposals.empty?
  end
end
