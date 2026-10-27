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
  # Which of the unread notifications need this person (D43). Read-only: the
  # notification center owns "read", so nothing here marks, snoozes or deletes.
  # A notification needs them when they were given the work or asked to look
  # after it, were mentioned, are asked something or asked to do something,
  # or it touches something they promised; the rest can wait.
  class InboxTriage
    LISTED = 15

    Item = Data.define(:notification, :why)

    def initialize(user)
      @user = user
    end

    attr_reader :user

    def unread
      @unread ||= Notification.visible(user).where(read_ian: false).includes(:actor, resource: :status)
                              .order(created_at: :desc).to_a
    end

    def items
      @items ||= unread.filter_map do |notification|
        why = reasons(notification)
        Item.new(notification:, why:) if why.any?
      end
    end

    def ignorable = unread - items.map(&:notification)

    private

    def reasons(notification)
      work_package_id = notification.resource_id
      [({ "kind" => "assigned_to_you" } if notification.reason_assigned? || notification.reason_responsible?),
       ({ "kind" => "mentioned" } if notification.reason_mentioned?),
       question_reason(work_package_id), promise_reason(work_package_id),
       ({ "kind" => "your_reminder" } if notification.reason_reminder?)].compact
    end

    def question_reason(work_package_id)
      asked, by = waiting_on_you[work_package_id]
      return unless asked

      { "kind" => "waiting_for_your_reply", "question" => asked.quote.truncate(120), "asked_by" => by&.name,
        "on" => asked.stated_at.to_date.iso8601 }
    end

    def promise_reason(work_package_id)
      promise = promises[work_package_id] or return
      { "kind" => "your_promise", "said" => promise.said_due_expression.presence || promise.quote.truncate(80),
        "on" => promise.stated_at.to_date.iso8601 }
    end

    def waiting_on_you
      @waiting_on_you ||= [*said.questions_for_me.map { [it, it.owner] }, *said.requests_for_me.map { [it, it.counterparty] }]
                          .select { |intent, _| intent.subject_type == "WorkPackage" }
                          .index_by { |intent, _| intent.subject_id }
    end

    def promises
      @promises ||= said.mine.select { it.subject_type == "WorkPackage" }.index_by(&:subject_id)
    end

    def said = @said ||= Assistant::Said.new(user)
  end
end
