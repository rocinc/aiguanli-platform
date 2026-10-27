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
  module Duties
    # Runs one duty, records what it produced, and counts the runs nobody
    # looked at: after four unseen runs in a row the delegator is asked whether
    # it is still needed (03 §8.5).
    class Runner
      IGNORED_AFTER = 7.days

      def initialize(duty, now: Time.current)
        @duty = duty
        @now = now
      end

      def call
        result = User.execute_as(@duty.delegator) { @duty.handler.new(@duty, now: @now).call }
        drafts = result.action_ids.presence || Array(@duty.last_result["drafts"])
        @duty.update!(last_run_at: @now, last_result: result.to_h.merge("at" => @now.iso8601, "drafts" => drafts),
                      unseen_runs: unseen_runs_after(drafts))
        ask_if_still_needed if @duty.stale?
        result
      end

      private

      # Only a draft that has gone a week without being opened or decided
      # counts as unseen, and a draft that is added to is still one draft.
      def unseen_runs_after(drafts)
        previous = Array(@duty.last_result["drafts"])
        return @duty.unseen_runs if previous.empty? || previous == drafts
        return 0 if opened?(previous)

        waited = Assistant::Action.exists?(id: previous, created_at: ..(@now - IGNORED_AFTER))
        waited ? @duty.unseen_runs + 1 : @duty.unseen_runs
      end

      def opened?(action_ids)
        Assistant::Action.where(id: action_ids).where.not(status: %w[proposed failed superseded]).exists? ||
          Assistant::Signal.where(action_id: action_ids).where.not(seen_at: nil).exists?
      end

      def ask_if_still_needed
        payload = OpenProject::LocaleHelper.with_locale_for(@duty.delegator) { still_needed_payload }
        Assistant::Signal.offer!(
          detector: "duty_unused", fingerprint: "#{@duty.id}:#{@duty.unseen_runs}", recipient: @duty.delegator,
          project: @duty.project, subject: @duty.project, channel: "brief", state: "pending", score: 0, deliver_at: @now,
          payload:
        )
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def still_needed_payload
        count = @duty.unseen_runs
        path = Rails.application.routes.url_helpers.project_assistant_desk_path(@duty.project, tab: "duties")
        { "headline" => I18n.t("assistant.duties.still_needed", duty: I18n.t("assistant.duties.kinds.#{@duty.kind}.title"), count:),
          "because" => [I18n.t("assistant.duties.still_needed_basis", count:)],
          "options" => [{ "label" => I18n.t("assistant.duties.still_needed_option"), "url" => path }], "duty_id" => @duty.id }
      end
    end
  end
end
