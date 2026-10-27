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
    # L1.3.1: a notice built on a fact that has since changed gives way. It
    # stays as a grey line for a day, and what it offered is taken back with it,
    # so nobody is asked to act on something that is no longer true.
    module Outdated
      module_function

      # How each detector's fact is overtaken: by any change on the object
      # after the moment the fact dates from, or by a status change after it.
      OVERTAKEN_BY = { "stalled" => :change, "merged_not_advanced" => :status, "said_done_still_open" => :status }.freeze

      def retract!(project)
        retract_overtaken(project)
        retract_done_as_said(project)
      end

      def retract_overtaken(project)
        live = Assistant::Signal.live.where(project:, subject_type: "WorkPackage")
        live.where(detector: OVERTAKEN_BY.keys).includes(:subject).find_each do |signal|
          since = signal.payload.dig("facts", "since")&.then { Time.zone.parse(it) }
          next unless since && signal.subject && overtaken?(signal.subject, since, OVERTAKEN_BY.fetch(signal.detector))

          retract(signal, OVERTAKEN_BY.fetch(signal.detector) == :change ? "change" : "status")
        end
      end

      # A change proposed from something said, which the person has since made by hand.
      def retract_done_as_said(project)
        live = Assistant::Signal.live.where(project:, detector: "said_change", subject_type: "WorkPackage")
        live.includes(:subject, :action).find_each do |signal|
          attributes = signal.action&.steps&.first&.dig("attributes")
          next unless signal.action&.proposed? && attributes.present?
          next unless attributes.all? { |name, value| signal.subject.attributes[name].to_s == value.to_s }

          retract(signal, "done_as_said")
        end
      end

      def overtaken?(work_package, since, kind)
        return work_package.journals.exists?(["created_at > ?", since]) if kind == :change

        Assistant::Event.where(subject: work_package, kind: "work_package.updated", created_at: (since + 1.second)..)
                        .any? { it.changed?("status_id") }
      end

      def retract(signal, reason)
        offered = [signal.action_id, *signal.options.filter_map { it["action_id"] }].compact
        Assistant::Action.proposed.where(id: offered).update_all(status: "superseded")
        signal.settle!("resolved", stale_reason: I18n.t("assistant.notice.stale_reasons.#{reason}", ref: "##{signal.subject_id}",
                                                                                      locale: signal.recipient.language.presence || I18n.locale))
      end
    end
  end
end
