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
  # The change someone proposed in a comment or on an agenda item, right
  # under the words that proposed it (06 S1): the ways to go, each with what
  # it would do, for the speaker to choose on the spot. Only the speaker
  # sees it; a settled one stays as one quiet line.
  class SourceSignalsComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    LINE_DETECTORS = %w[meeting_unowned meeting_related_decision meeting_checklist].freeze

    def self.signals_for(source, user)
      return [] if source.nil? || user.nil? || !user.logged?

      Assistant::Signal.where(recipient: user, channel: "inline")
                       .where("payload ->> 'source_gid' = ?", source.to_gid.to_s)
                       .where("outcome IS NULL OR outcome_at > ?", 1.day.ago)
                       .includes(:action).order(:created_at).to_a
    end

    # Proposals for a meeting arrive after the page was drawn. Each agenda
    # item keeps a frame that is there even while empty; the page listens on
    # one signed stream per person and meeting, and the stream only names the
    # frame to reload (NOTIFY carries < 8000 bytes), never the cards.
    def self.frame_id(source) = "assistant-proposals-#{source.class.name.underscore.dasherize}-#{source.id}"

    def self.stream_for(meeting, user) = [user, meeting, :assistant_proposals]

    def self.signed_stream(meeting, user) = Turbo::StreamsChannel.signed_stream_name(stream_for(meeting, user))

    def self.broadcast_reload(source, users)
      return unless source.is_a?(MeetingAgendaItem)

      html = reload_frame(source)
      Array(users).compact.uniq.each do |user|
        Turbo::StreamsChannel.broadcast_replace_to(stream_for(source.meeting, user), target: frame_id(source), html:)
      end
    rescue StandardError => e
      Rails.logger.warn("[assistant] proposals broadcast #{source.id}: #{e.class} #{e.message}")
    end

    def self.reload_frame(source)
      src = Rails.application.routes.url_helpers.assistant_agenda_item_proposals_path(source)
      ActionController::Base.helpers.tag.turbo_frame(id: frame_id(source), src:)
    end

    def initialize(source:, user:, signals: nil, frame: false)
      super()
      @source = source
      @user = user
      @signals = signals
      @frame = frame
    end

    attr_reader :source, :user

    def signals = @signals ||= self.class.signals_for(source, user)

    def render? = @frame || signals.any?

    def call
      return cards unless @frame

      helpers.turbo_frame_tag(self.class.frame_id(source)) { cards }
    end

    private

    def cards
      return hint if shown.empty?

      content_tag(:div, class: "assistant-source-signals", data: { test_selector: "assistant-source-signals" }) do
        safe_join(shown.map { render_signal(it) })
      end
    end

    def render_signal(signal)
      return render(Assistant::AnswerLineComponent.new(signal:, user:)) if Assistant::AnswerLineComponent.for?(signal)

      notice = render(Assistant::NoticeComponent.new(signal:, user:, density: line?(signal) ? :line : :card, heading_level: 4))
      return notice unless line?(signal)

      content_tag(:div, safe_join([notice, intent_verbs(signal)]), class: "assistant-source-line")
    end

    def intent_verbs(signal)
      return unless signal.detector == Assistant::Understanding::UnownedItems::DETECTOR

      intent = Assistant::Intent.visible(user).find_by(id: signal.payload["intent_id"])
      return unless intent

      render(Assistant::IntentVerbsComponent.new(intent:, user:, meeting: source.try(:meeting), lead: "assign"))
    end

    # One line per agenda item: what someone proposed outranks the host's
    # reminder to give a promise an owner.
    def shown
      @shown ||= begin
        hints, proposals = signals.reject { set_aside?(it) }.partition { line?(it) }
        proposals.presence || [hints.min_by { [it.stale? ? 1 : 0, LINE_DETECTORS.index(it.detector)] }].compact
      end
    end

    def line?(signal) = LINE_DETECTORS.include?(signal.detector)

    def set_aside?(signal)
      id = signal.payload["intent_id"]
      id.present? && Assistant::Intent.where(id:, status: "dismissed").exists?
    end

    def hint
      text, url = work_package_hint
      return "".html_safe unless text

      content_tag(:p, class: "assistant-source-hint", data: { test_selector: "assistant-source-hint" }) do
        safe_join([render(Primer::Beta::Octicon.new(icon: :"sparkle-fill", size: :small, "aria-hidden": true)),
                   url ? link_to(text, url, data: { turbo_frame: "_top" }) : text])
      end
    end

    def work_package_hint
      work_package = source.try(:work_package)
      return unless work_package && Assistant::Facts.open?(work_package) && work_package.due_date.present? &&
                    work_package.due_date < Date.current && work_package.visible?(user)

      [t("assistant.meeting_recap.hints.late", ref: "##{work_package.id}", date: Assistant::Text.day(work_package.due_date),
                                               days: (Date.current - work_package.due_date).to_i, status: work_package.status.name),
       helpers.work_package_path(work_package)]
    end
  end
end
