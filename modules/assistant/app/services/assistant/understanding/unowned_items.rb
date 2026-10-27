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
  module Understanding
    # A promise made at a meeting that nobody took (S6.2): once the meeting's
    # notes are read, the host gets one line under the agenda item with the
    # two people who could take it, each a work package ready to create.
    # One line per item, so only its first unclaimed promise is offered.
    class UnownedItems
      DETECTOR = "meeting_unowned"
      OPTIONS = 2
      HORIZON = 14.days

      def self.offer(agenda_item, items) = new(agenda_item, items).call

      # The offer that was taken: the promise now has its owner and its work
      # package, so the next meeting no longer lists it as unclaimed.
      def self.taken(action)
        return unless action.kind == "meeting_action_item" && action.executed?

        signal = Assistant::Signal.where(detector: DETECTOR).where("payload -> 'options' @> ?",
                                                                 [{ action_id: action.id }].to_json).first or return
        item = promise_of(signal) or return
        step = action.steps.first
        owner = User.find_by(id: step.dig("attributes", "assigned_to_id"))
        created = action.inverse.detect { it["type"] == "WorkPackage" }
        item.update!(owner:, work_package_id: created ? created["id"] : step["id"])
      end

      # Someone took it some other way (the verbs under the line, a comment):
      # what was offered for it is no longer true.
      def self.settled(intent)
        Assistant::Signal.live.where(detector: DETECTOR).where("payload ->> 'intent_id' = ?", intent.id.to_s).group_by do
          it.payload["agenda_item_id"]
        end.each_value { |signals| retire(signals) }
      end

      def self.retire(signals)
        ids = signals.flat_map { |signal| signal.payload["options"].filter_map { it["action_id"] } }
        Assistant::Action.proposed.where(id: ids).update_all(status: "superseded") if ids.any?
        Assistant::Signal.where(id: signals.map(&:id)).update_all(state: "expired", outcome: "resolved", outcome_at: Time.current)
        item = MeetingAgendaItem.find_by(id: signals.first.payload["agenda_item_id"])
        Assistant::SourceSignalsComponent.broadcast_reload(item, signals.map(&:recipient).uniq) if item
      end

      # A new reading of the item replaces its promises; the one that was
      # offered is found again by what it said.
      def self.promise_of(signal)
        Assistant::Intent.find_by(id: signal.payload["intent_id"]) ||
          Assistant::Intent.where(source_type: "MeetingAgendaItem", source_id: signal.payload["agenda_item_id"],
                                  title: signal.payload["title"], owner_id: nil).first
      end

      def initialize(agenda_item, items)
        @agenda_item = agenda_item
        @items = Intent.where(id: Array(items).map(&:id)).includes(:work_package).order(:stated_at).to_a
      end

      def call
        item = @items.detect { unclaimed?(it) }
        return withdraw(nil) unless item

        host = decider or return
        return if Assistant::Signal.silenced?(DETECTOR, recipient: host, project:)

        key = Digest::MD5.hexdigest(item.title)[0, 8]
        return if Assistant::Signal.exists?(detector: DETECTOR, fingerprint: fingerprint(key, "inline"))

        withdraw(key)
        OpenProject::LocaleHelper.with_locale_for(host) do
          actions = candidates(host).filter_map { propose(item, it, host) }
          signal!(item, host, actions, key) if actions.any?
        end
      end

      private

      def fingerprint(key, channel) = "#{@agenda_item.to_gid}|#{key}|#{channel}"

      # What was offered for a promise that is gone or taken is no longer
      # true; the line under the item goes away and its proposals with it.
      def withdraw(keep)
        live = Assistant::Signal.live.where(detector: DETECTOR).where("payload ->> 'source_gid' = ?", @agenda_item.to_gid.to_s)
        live = live.where.not("fingerprint LIKE ?", "%|#{keep}|%") if keep
        signals = live.to_a
        return if signals.empty?

        self.class.retire(signals)
      end

      def meeting = @agenda_item.meeting

      def project = meeting.project

      def unclaimed?(item)
        item.kind == "commitment" && item.live? && item.owner_id.nil? && item.strength != "trivial" &&
          item.work_package&.assigned_to_id.nil?
      end

      def decider
        [meeting.author, @agenda_item.presenter].find do
          it.is_a?(User) && it.active? && !it.is_a?(AssistantUser) && it.allowed_in_project?(:add_work_packages, project)
        end
      end

      def candidates(host)
        assignable = Principal.possible_assignee(project).where(id: meeting.participants.select(:user_id)).where(status: Principal.statuses[:active])
                              .where.not(type: "AssistantUser").to_a
        assignable = assignable.select { Assistant::Facts::Capacity.new(it, Date.current, Date.current + HORIZON).hours.positive? }
        presenter, others = assignable.partition { it == @agenda_item.presenter }
        ordered = others.sort_by { -Assistant::Facts::Load.new(it, Date.current, Date.current + HORIZON).free_hours }
        [*presenter, *ordered].first(OPTIONS)
      end

      def propose(item, person, host)
        action = Assistant::Actions::Propose.call(
          kind: "meeting_action_item", title: I18n.t("assistant.meeting_recap.unowned.option", name: person.name),
          steps: [step(item, person)], on_behalf_of: host, project:, subject: meeting,
          basis: [Assistant::Basis.for(item.source, quote: item.quote)], auto_execute: false
        )
        [person, action] unless action.status == "failed"
      end

      def step(item, person)
        if item.work_package_id
          { "op" => "update_work_package", "type" => "WorkPackage", "id" => item.work_package_id,
            "attributes" => { "assigned_to_id" => person.id } }
        else
          { "op" => "create_work_package",
            "attributes" => { "project_id" => project.id, "subject" => item.title.truncate(200), "assigned_to_id" => person.id,
                              "due_date" => item.said_due_on&.iso8601 }.compact }
        end
      end

      def signal!(item, host, proposed, key)
        options = proposed.map do |person, action|
          { "label" => action.title, "consequence" => I18n.t("assistant.meeting_recap.unowned.consequence",
                                                           subject: item.title.truncate(60), name: person.name),
            "action_id" => action.id }
        end
        create_signal!(item, host, [], "inline", key)
        create_signal!(item, host, options, "brief", key)
        Assistant::SourceSignalsComponent.broadcast_reload(@agenda_item, [host])
      end

      def headline(item)
        room = 40
        if I18n.locale.to_s.start_with?("zh", "ja", "ko")
          room = (Assistant::Proactive::Detectors::Base::HEADLINE_LIMIT - I18n.t("assistant.meeting_recap.unowned.headline", title: "").length).clamp(8, 40)
        end
        I18n.t("assistant.meeting_recap.unowned.headline", title: item.title.truncate(room))
      end

      def create_signal!(item, host, options, channel, key)
        Assistant::Signal.offer!(
          detector: DETECTOR, fingerprint: fingerprint(key, channel), recipient: host, project:, subject: meeting,
          action_id: options.first&.fetch("action_id"), channel:, state: "pending", score: 20, deliver_at: Time.current,
          payload: { "headline" => headline(item),
                     "because" => ["“#{item.quote}”"], "why" => "hosts", "nature" => "decision", "options" => options,
                     "source_gid" => @agenda_item.to_gid.to_s, "agenda_item_id" => @agenda_item.id, "intent_id" => item.id,
                     "title" => item.title }
        )
      rescue ActiveRecord::RecordNotUnique
        nil
      end
    end
  end
end
