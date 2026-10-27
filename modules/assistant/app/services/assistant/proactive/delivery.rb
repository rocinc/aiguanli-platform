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
  module Proactive
    # Sends what is due. A notification goes through the platform's in-app
    # notifications with reason :assistant and never into the mail digest; if
    # the person's interruption budget is used up by then, it waits for the
    # brief instead. A public comment is the assistant's own T1 comment.
    # Brief and inline signals become visible where they are read.
    class Delivery
      def initialize(now: Time.current)
        @now = now
      end

      def call
        Assistant::Signal.where(state: "pending").where(deliver_at: ..@now).includes(:recipient, :project, :subject, :action)
                         .find_each { deliver(it) }
        Assistant::Signal.where(state: "held", outcome: [nil, "snoozed"]).where(snoozed_until: ..@now)
                         .update_all(state: "pending", outcome: nil, outcome_at: nil, snoozed_until: nil, deliver_at: @now)
      end

      def deliver(signal)
        return expire!(signal) if gone?(signal)

        case signal.channel
        when "notification" then notify(signal)
        when "comment" then comment(signal)
        else signal.update!(state: "delivered", delivered_at: @now)
        end
      rescue StandardError => e
        Rails.logger.error("[assistant] delivery of signal #{signal.id} failed: #{e.class} #{e.message}")
      end

      private

      def gone?(signal)
        (signal.subject_type.present? && signal.subject.nil?) || !signal.recipient.active? ||
          (signal.project && !signal.project.module_enabled?(:assistant))
      end

      def expire!(signal) = signal.update!(state: "expired")

      def notify(signal)
        preference = Assistant::Preference.effective(signal.recipient, signal.project)
        timing = Timing.new(signal.recipient, now: @now)
        unless timing.may_interrupt?(preference.cap)
          return signal.update!(channel: "brief", deliver_at: timing.working_now? ? @now : timing.next_brief_at,
                                payload: signal.payload.merge("demoted" => "over_budget"))
        end

        resource = signal.subject.is_a?(WorkPackage) || signal.subject.is_a?(Project) ? signal.subject : signal.project
        call = Notifications::CreateService.new(user: Assistant.user).call(
          recipient_id: signal.recipient_id, actor: Assistant.user, resource:, reason: :assistant,
          subject: signal.headline.to_s.truncate(255), mail_reminder_sent: nil, mail_alert_sent: nil
        )
        if call.success?
          signal.update!(state: "delivered", delivered_at: @now,
                         payload: signal.payload.merge("notification_id" => call.result.id))
        else
          signal.update!(channel: "brief", deliver_at: @now)
        end
      end

      def comment(signal)
        action = Assistant::Action.find_by(id: signal.payload["public_comment_action_id"])
        Assistant::Actions::Execute.call(action, decided_by: nil) if action&.proposed?
        return signal.update!(channel: "brief") unless action&.reload&.executed?

        signal.update!(state: "delivered", delivered_at: @now)
      end
    end
  end
end
