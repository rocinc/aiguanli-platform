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
  # The one line under an object's title (S3): what the assistant has to say
  # to this person about this object. Capacity is one; whatever else is
  # alive for the same person waits behind a fold.
  class ObjectLineComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    Entry = Data.define(:kind, :value)

    def self.live_for(user)
      Assistant::Signal.live.where(recipient: user)
                       .where("channel = 'inline' OR (channel = 'notification' AND state = 'delivered')")
                       .where("payload ->> 'source_gid' IS NULL")
                       .where(Assistant::Proactive::Immediate.not_fresh_sql)
                       .where("snoozed_until IS NULL OR snoozed_until <= ?", Time.current)
                       .order(score: :desc, created_at: :desc)
    end

    def self.signals_for(object, user)
      return [] if object.nil? || user.nil? || !user.logged?

      live_for(user).where(subject: object).includes(:action).to_a
    end

    def initialize(object:, user:)
      super()
      @object = object
      @user = user
    end

    attr_reader :object, :user

    def project = object.is_a?(Project) ? object : object.try(:project)

    def render? = Surface.available?(project, user) && entries.any?

    def entries
      @entries ||= [*signals.map { Entry.new(:signal, it) }, *stale.map { Entry.new(:signal, it) }, *readiness_entry,
                    *proposals_entry]
    end

    def primary = entries.first

    def behind = entries.drop(1)

    def folded
      @folded ||= [*behind, *follow_ups.map { Entry.new(:follow_up, it) }]
    end

    def signals = @signals ||= self.class.signals_for(object, user)

    def stale
      return [] if signals.any?

      @stale ||= Assistant::Signal.recently_stale.where(subject: object, recipient: user).order(outcome_at: :desc).limit(1).to_a
    end

    def readiness = @readiness ||= (Assistant::ReadinessLine.new(object) if object.is_a?(Version))

    def proposals
      @proposals ||= Surface.new(subject: object, user:).proposals.select { it.decidable_by?(user) }
    end

    def follow_ups
      return [] unless object.is_a?(WorkPackage)

      @follow_ups ||= Assistant::FollowUp.where(work_package: object, place_type: "Message").includes(:place)
                                         .select { it.place&.visible?(user) }
    end

    def call
      content_tag(:div, class: "assistant-object-line", role: "region", "aria-label": t("assistant.object_line.label"),
                        data: { test_selector: "assistant-object-line" }) do
        safe_join([block(primary), (more if folded.any?)].compact)
      end
    end

    private

    def block(entry)
      case entry.kind
      when :signal then notice(entry.value)
      when :readiness then readiness_fold(entry.value)
      when :proposals then fold(awaiting, "proposals") { cards(entry.value) }
      when :follow_up then origin(entry.value)
      end
    end

    def notice(signal) = render(Assistant::NoticeComponent.new(signal:, user:, density: :line, heading_level: 2))

    def readiness_fold(line) = fold(line.sentence, "readiness") { facts(line.details) }

    def more
      content_tag(:details, class: "assistant-object-line--more", data: { test_selector: "assistant-object-line-more" }) do
        safe_join([content_tag(:summary, safe_join([chevron, t("assistant.object_line.more", count: folded.size)]),
                               class: "assistant-object-line--more-summary"),
                   content_tag(:div, safe_join(folded.map { block(it) }), class: "assistant-object-line--folded")])
      end
    end

    def fold(sentence, kind)
      content_tag(:details, class: "assistant-notice assistant-notice--line assistant-notice--fold",
                            data: { test_selector: "assistant-object-line-#{kind}" }) do
        safe_join([content_tag(:summary, class: "assistant-notice--row assistant-notice--summary") do
                     safe_join([mark, content_tag(:div, content_tag(:p, sentence, class: "assistant-notice--headline"),
                                                  class: "assistant-notice--body"),
                                content_tag(:span, chevron, class: "assistant-notice--toggle")])
                   end,
                   content_tag(:div, yield, class: "assistant-notice--main")])
      end
    end

    def facts(lines)
      content_tag(:ul, safe_join(lines.map { content_tag(:li, it) }), class: "assistant-object-line--facts")
    end

    def cards(actions)
      items = actions.map do |action|
        content_tag(:li, render(Assistant::ActionCardComponent.new(action:, user:, variant: :compact, heading_level: 4)))
      end
      content_tag(:ul, safe_join(items), class: "assistant-object-line--cards")
    end

    def origin(follow_up)
      link = link_to(follow_up.place.subject.truncate(60), Assistant::Provenance.message_url(follow_up.place, helpers),
                     data: { turbo_frame: "_top" })
      content_tag(:p, class: "assistant-object-line--origin", data: { test_selector: "assistant-object-line-origin" }) do
        safe_join([mark, content_tag(:span, safe_join([t("assistant.object_line.from_forum_html", link:),
                                                       t("assistant.object_line.from_forum_state.#{follow_up.state}")], " "))])
      end
    end

    def awaiting = t("assistant.object_line.awaiting", count: proposals.size)

    def mark = render(Primer::Beta::Octicon.new(icon: :"sparkle-fill", size: :small, color: :muted, "aria-hidden": true))

    def chevron
      render(Primer::Beta::Octicon.new(icon: :"chevron-right", size: :xsmall, classes: "assistant-notice--chevron",
                                       "aria-hidden": true))
    end

    def readiness_entry = readiness&.sentence ? [Entry.new(:readiness, readiness)] : []

    def proposals_entry = proposals.any? ? [Entry.new(:proposals, proposals)] : []
  end
end
