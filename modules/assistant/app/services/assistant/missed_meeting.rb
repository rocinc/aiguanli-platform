# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  # A closed meeting, told in three sentences to each person who was invited
  # and did not attend (04 D1): what was decided, what is now theirs, what
  # comes next. Written once per meeting and language; the decisions and
  # their own items are read off the record, never left to the model.
  class MissedMeeting
    SYSTEM = <<~PROMPT
      Summarise a meeting for someone who was invited and missed it, in exactly three short sentences:
      what was decided, what was asked of the team, what happens next. Reply as JSON {"summary": string}.
      Only what the material says; no names beyond those given; write in the language given.
    PROMPT

    def initialize(meeting, llm: nil)
      @meeting = meeting
      @llm = llm
    end

    attr_reader :meeting

    def call
      return [] unless meeting.project&.module_enabled?(:assistant)

      absent = meeting.participants.includes(:user).reject(&:attended?).filter_map(&:user)
                      .select { it.active? && Assistant::Surface.available?(meeting.project, it) }
                      .reject { Assistant::Signal.silenced?("missed_meeting", recipient: it, project: meeting.project) }
      summaries = {}
      absent.filter_map do |person|
        summary = summaries[person.language.presence || Setting.default_language] ||=
          OpenProject::LocaleHelper.with_locale_for(person) { summary_for(person) }
        next if summary.blank?

        signal!(person, summary)
      end
    end

    private

    def material
      @material ||= Assistant::Duties::MeetingFollowup.minutes_material(meeting)
    end

    def summary_for(person)
      return decisions_line unless usable?

      llm(person).json(system: SYSTEM, user: JSON.generate("language" => I18n.locale.to_s, "material" => material),
                       max_tokens: 600)["summary"].to_s.strip
    rescue Assistant::Llm::Error
      nil
    end

    def decisions_line
      decided = material["said"].select { it["kind"] == "decision" }.map { it["title"] }
      decided.any? ? I18n.t("assistant.missed_meeting.decided", list: decided.first(5).join("；")) : nil
    end

    def usable? = Assistant::Llm.configured? && !Assistant::Usage.near_budget?(project: meeting.project)

    def llm(person) = @llm || Assistant::Llm.new(purpose: "missed_meeting", user: person, project: meeting.project)

    def signal!(person, summary)
      theirs = Assistant::Intent.where(subject: meeting, owner: person).live.map(&:title)
      because = [summary, *theirs.first(5).map { I18n.t("assistant.missed_meeting.yours", title: it) }]
      Assistant::Signal.offer!(
        detector: "missed_meeting", fingerprint: "meeting:#{meeting.id}", recipient: person, project: meeting.project,
        subject: meeting, channel: "brief", state: "pending", score: 20, deliver_at: Time.current,
        payload: { "headline" => I18n.t("assistant.missed_meeting.headline", meeting: meeting.title), "because" => because,
                   "nature" => "object",
                   "options" => [{ "label" => I18n.t("assistant.missed_meeting.open"),
                                   "url" => OpenProject::StaticRouting::StaticUrlHelpers.new.meeting_path(meeting) }] }
      )
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
