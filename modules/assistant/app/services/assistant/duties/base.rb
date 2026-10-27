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
    # A standing job handed to the assistant. Each kind says when it is due
    # and what it does; whatever it changes goes through Propose on behalf of
    # the delegator, so the tier, the signature and undo are the same as
    # anywhere else. What needs the delegator's go-ahead reaches them as a
    # signal in their brief.
    class Base
      class << self
        def due?(duty, now = Time.current) = raise NotImplementedError

        def schedule_label(_duty) = nil

        private

        def local(duty, now) = now.in_time_zone(duty.delegator.time_zone || Time.zone)

        def ran_since?(duty, time) = duty.last_run_at.present? && duty.last_run_at >= time

        def weekly(duty, now, wday:, hour:)
          at = local(duty, now)
          slot = at.beginning_of_week + (wday - 1).days + hour.hours
          at >= slot && !ran_since?(duty, slot)
        end

        def daily(duty, now, hour:)
          at = local(duty, now)
          slot = at.beginning_of_day + hour.hours
          at >= slot && Assistant::Facts.working_day?(at.to_date) && !ran_since?(duty, slot)
        end

        def every(duty, now, interval) = duty.last_run_at.nil? || duty.last_run_at <= now - interval
      end

      Result = Data.define(:summary, :action_ids, :produced) do
        def self.nothing(summary = nil) = new(summary:, action_ids: [], produced: false)

        def to_h = { "summary" => summary, "action_ids" => action_ids, "produced" => produced }
      end

      def initialize(duty, now: Time.current, llm: nil)
        @duty = duty
        @now = now
        @llm = llm
      end

      def call = raise NotImplementedError

      private

      attr_reader :duty, :now

      def project = duty.project

      def delegator = duty.delegator

      def today = now.in_time_zone(delegator.time_zone || Time.zone).to_date

      def scope = duty.scope.to_h

      def basis = [Assistant::Basis.for(duty)]

      def propose(kind:, title:, steps:, subject: nil, auto_execute: true)
        Assistant::Actions::Propose.call(kind:, title:, steps:, on_behalf_of: delegator, project:, subject:, basis:,
                                         auto_execute: auto_execute && scope["ceiling"] != "draft")
      end

      # Something that waits for the delegator becomes a signal in their brief.
      def offer(action, headline:, because: [], subject: nil, options: nil)
        return action if action.executed? || action.status == "failed"
        return withdraw(action) if silenced?

        Assistant::Signal.create!(
          detector: "duty_#{duty.kind}", fingerprint: "#{duty.id}:#{action.id}", recipient: delegator, project:,
          subject: subject || action.subject, action:, channel: "brief", state: "pending", score: 0, deliver_at: now,
          payload: { "headline" => headline, "because" => because, "why_me" => I18n.t("assistant.duties.why", duty: title),
                     "options" => options || [{ "label" => action.title, "action_id" => action.id }], "duty_id" => duty.id }
        )
        action
      rescue ActiveRecord::RecordNotUnique
        action
      end

      def silenced? = Assistant::Signal.silenced?("duty_#{duty.kind}", recipient: delegator, project:)

      def withdraw(action)
        action.update!(status: "superseded")
        action
      end

      def title = I18n.t("assistant.duties.kinds.#{duty.kind}.title")

      def llm = @llm ||= Assistant::Llm.new(purpose: "duty_#{duty.kind}", user: delegator, project:)

      def write(system, material, max_tokens: 3500)
        edits = earlier_edits
        material = material.merge("earlier_edits" => edits) if edits.any?
        OpenProject::LocaleHelper.with_locale_for(delegator) do
          llm.json(system: "#{system}\nWrite in this language: #{I18n.locale}. Never quote the field names of the material; " \
                           "say what they mean. Answer as JSON.#{EDITS_HINT if edits.any?}", user: JSON.generate(material),
                   max_tokens:)
        end
      end

      EDITS_HINT = " The material holds earlier_edits: how the delegator last rewrote drafts like this one (before, after). " \
                   "Write the way the after texts read."

      def earlier_edits = Assistant::Revisions.examples(delegator, duty.kind)

      def l(date) = Assistant::Text.day(date)
    end
  end
end
