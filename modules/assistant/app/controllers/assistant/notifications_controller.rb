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
  # What an assistant notification in the notification center is about. JSON
  # gives the line the center shows (headline, why, where to act); HTML
  # takes the person to the place where they can act on it. Only the
  # recipient may ask.
  class NotificationsController < ApplicationController
    before_action :require_login
    before_action :find_notification
    authorization_checked! :show

    def show
      signal = find_signal
      Assistant::Proactive::Feedback.seen!([signal]) if signal

      respond_to do |format|
        format.json { render json: payload(signal) }
        format.html { redirect_to(target_url(signal)) }
      end
    end

    private

    def find_notification
      @notification = Notification.where(recipient: current_user, reason: :assistant).find(params.expect(:id))
    end

    def find_signal
      Assistant::Signal.where(recipient: current_user)
                       .where("payload ->> 'notification_id' = ?", @notification.id.to_s)
                       .order(created_at: :desc).first
    end

    def payload(signal)
      return { gone: t("assistant.notification.gone"), url: my_page_path } if signal.nil?

      { headline: signal.headline.presence || @notification.subject,
        why: signal.why_me,
        settled: settled(signal),
        url: target_url(signal),
        open_label: t("assistant.notification.open") }.compact
    end

    def settled(signal)
      return if signal.outcome.nil?

      t("assistant.signal.outcomes.#{signal.outcome}", default: t("assistant.signal.outcomes.resolved"))
    end

    def target_url(signal)
      subject = signal&.subject
      return fallback_url(signal) unless subject.respond_to?(:visible?) && subject.visible?(current_user)

      case subject
      when WorkPackage then work_package_path(subject)
      when Meeting then meeting_path(subject)
      when Version then version_path(subject)
      when WikiPage then project_wiki_path(subject.project, subject)
      when ::Message then Assistant::Provenance.message_url(subject, helpers)
      else fallback_url(signal)
      end
    end

    def fallback_url(signal) = signal&.project ? project_overview_path(signal.project) : my_page_path
  end
end
