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
  # The one section the assistant adds at the top of an agenda (S6.1): what
  # the last meeting left open, what is due, what waits for an answer. The
  # same lines the host may have put in the agenda are not repeated here.
  class MeetingRecapComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    WINDOW = 2.days
    MARKS = ["\u0001O", "\u0001P"].freeze

    def initialize(meeting:, user:)
      super()
      @meeting = meeting
      @user = user
    end

    attr_reader :meeting, :user

    def recap = @recap ||= Assistant::MeetingRecap.new(meeting, user)

    def render?
      upcoming? && Assistant::Surface.available?(meeting.project, user) && (recap.entries.any? || recap.landed.positive?)
    end

    def call
      content_tag(:section, class: "assistant-notice assistant-recap", "aria-labelledby": title_id,
                            data: { test_selector: "assistant-meeting-recap" }) do
        safe_join([heading, (recap.entries.any? ? groups : quiet)])
      end
    end

    private

    def upcoming?
      !meeting.template? && !meeting.closed? && !meeting.cancelled? && meeting.start_time.present? &&
        meeting.start_time <= WINDOW.from_now
    end

    def title_id = "assistant-recap-#{meeting.id}-title"

    def heading
      content_tag(:div, class: "assistant-notice--row") do
        safe_join([render(Primer::Beta::Octicon.new(icon: :"sparkle-fill", size: :small, color: :muted, "aria-hidden": true)),
                   content_tag(:h3, t("assistant.meeting_recap.title"), id: title_id, class: "assistant-recap--title")])
      end
    end

    def groups
      safe_join(recap.sections.filter_map { |key, entries| group(key, entries) if entries.any? })
    end

    def group(key, entries)
      content_tag(:div, class: "assistant-recap--group", data: { test_selector: "assistant-meeting-recap-#{key}" }) do
        safe_join([content_tag(:h4, t("assistant.meeting_recap.groups.#{key}"), class: "assistant-recap--group-title"),
                   list(entries), (older if key == :due)])
      end
    end

    def list(entries) = content_tag(:ul, safe_join(entries.map { item(it) }), class: "assistant-recap--list")

    def item(entry)
      content_tag(:li, class: "assistant-recap--item", data: { test_selector: "assistant-meeting-recap-item" }) do
        safe_join([content_tag(:div, safe_join([who(entry), line(entry), load_hint(entry)].compact), class: "assistant-recap--text"),
                   verbs(entry)].compact)
      end
    end

    def verbs(entry)
      return unless entry.intent && !recap.shared?

      render(Assistant::IntentVerbsComponent.new(intent: entry.intent, user:, meeting:))
    end

    def load_hint(entry)
      intent = entry.intent
      owner, = Assistant::IntentVerbs.speakers(intent, user) if intent&.commitment_like?
      return unless owner && owner != user

      render(Assistant::PersonLoadHintComponent.new(person: owner, always: false))
    end

    def who(entry)
      intent = entry.intent or return
      owner, other = Assistant::IntentVerbs.speakers(intent, user)
      return if owner.nil? || (owner == user && intent.commitment_like?)

      key = Assistant::IntentVerbs.kind_of(intent)
      key = "#{key}_with" if other && key.in?(%w[commitment question])
      sentence = I18n.t("assistant.meeting_recap.who.#{key}", owner: MARKS.first, other: MARKS.last)
      names = { MARKS.first => person(owner), MARKS.last => person(other) }
      sentence = sentence.gsub(/ ?(#{Regexp.union(MARKS)}) ?/) { names[Regexp.last_match(1)] == you ? you : Regexp.last_match(0) }
      content_tag(:span, safe_join(sentence.split(/(#{Regexp.union(MARKS)})/).map { names.fetch(it, it) }),
                  class: "assistant-recap--who", data: { test_selector: "assistant-meeting-recap-who" })
    end

    def you = t("assistant.meeting_recap.who.you")

    def person(person)
      return unless person
      return you if person == user

      Assistant::PersonInText.person(self, person)
    end

    def older
      return if recap.older_due.empty?

      key = recap.older_late? ? "older_late" : "older"
      content_tag(:details, class: "assistant-recap--older", data: { test_selector: "assistant-meeting-recap-older" }) do
        safe_join([content_tag(:summary, t("assistant.meeting_recap.#{key}", count: recap.older_due.size)), list(recap.older_due)])
      end
    end

    def line(entry)
      entry.url ? link_to(entry.line, entry.url) : entry.line
    end

    def quiet
      content_tag(:p, t("assistant.meeting_recap.all_landed", count: recap.landed), class: "assistant-recap--quiet")
    end
  end
end
