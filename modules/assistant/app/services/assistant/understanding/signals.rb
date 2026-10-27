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
  module Understanding
    # The other things a message said (02 §2.1), turned into proposals for
    # the people they concern: a dependency or a split of a work package, time
    # off, time already spent, a risk, a piece of knowledge. Nothing is
    # guessed: an unnamed work package, an unknown person or an unreadable
    # date drops the signal. Each is offered, never done unasked, except that
    # someone's own time entry or time off is T1 for themselves.
    class Signals
      RISK_PAGE = { "zh-CN" => "风险登记", "en" => "Risk register" }.freeze
      GLOSSARY_PAGE = { "zh-CN" => "术语表", "en" => "Glossary" }.freeze

      def self.for(source, raw)
        new(source, Array(raw)).call
      end

      def initialize(source, raw)
        @source = source
        @raw = raw
        @said = SaidChanges.new(source, [])
      end

      def call
        @raw.filter_map do |signal|
          signal = signal.to_h.stringify_keys
          next unless signal["certainty"].in?(%w[certain firm likely])

          case signal["type"]
          when "dependency" then dependency(signal)
          when "split" then split(signal)
          when "time_off" then time_off(signal)
          when "time_spent" then time_spent(signal)
          when "risk" then risk(signal)
          when "knowledge" then knowledge(signal)
          end
        end
      end

      private

      attr_reader :source, :said

      delegate :project, :speaker, :stated_on, to: :said

      def dependency(signal)
        wp = said.resolve_target(signal["target"]) or return
        before = said.resolve_target(signal["on"].presence || "none") or return
        return if before == wp || Relation.exists?(from: before, to: wp) || Relation.exists?(from: wp, to: before)

        lag = signal["lag_days"].to_i.clamp(0, 60)
        offer(signal, kind: "said_dependency", subject: wp, decider: decider_for(wp),
                      title: I18n.t("assistant.understanding.signals.dependency", ref: "##{wp.id}", before: "##{before.id}"),
                      steps: [{ "op" => "create_relation",
                                "attributes" => { "from_id" => wp.id, "to_id" => before.id, "relation_type" => "follows",
                                                  "lag" => lag.positive? ? lag : nil }.compact }])
      end

      def split(signal)
        wp = said.resolve_target(signal["target"]) or return
        parts = Array(signal["parts"]).map { it.to_s.strip }.compact_blank.first(8)
        return if parts.size < 2 || wp.children.exists?

        offer(signal, kind: "said_split", subject: wp, decider: decider_for(wp),
                      title: I18n.t("assistant.understanding.signals.split", ref: "##{wp.id}", count: parts.size),
                      steps: parts.map do |subject|
                        { "op" => "create_work_package",
                          "attributes" => { "project_id" => project.id, "type_id" => wp.type_id, "subject" => subject.truncate(255),
                                            "parent_id" => wp.id, "assigned_to_id" => wp.assigned_to_id }.compact }
                      end)
      end

      def time_off(signal)
        person = signal["member_id"].present? ? said.person(signal["member_id"]) : speaker
        return unless person
        return unless person == speaker || speaker.nil?

        from = date(signal["from"]) or return
        to = date(signal["to"]) || from
        return if to < from || (to - from) > 60

        offer(signal, kind: "said_time_off", subject: project, decider: person,
                      title: I18n.t("assistant.understanding.signals.time_off", name: person.name, from: day(from), to: day(to)),
                      steps: [{ "op" => "create_non_working_time",
                                "attributes" => { "user_id" => person.id, "start_date" => from.iso8601, "end_date" => to.iso8601 } }])
      end

      def time_spent(signal)
        return unless speaker

        wp = said.resolve_target(signal["target"]) or return
        hours = Float(signal["hours"], exception: false)
        return unless hours&.positive? && hours <= 24

        on = date(signal["on"]) || stated_on
        return if TimeEntry.exists?(entity: wp, user: speaker, spent_on: on, hours:)

        offer(signal, kind: "said_time_spent", subject: wp, decider: speaker,
                      title: I18n.t("assistant.understanding.signals.time_spent", hours:, ref: "##{wp.id}", on: day(on)),
                      steps: [{ "op" => "create_time_entry",
                                "attributes" => { "work_package_id" => wp.id, "user_id" => speaker.id, "hours" => hours,
                                                  "spent_on" => on.iso8601, "comments" => signal["quote"].truncate(255) } }])
      end

      # A risk goes into the project's risk register page, one line with its
      # source, and is shown to whoever answers for the work it threatens.
      def risk(signal)
        return unless project.wiki

        wp = said.resolve_target(signal["target"].presence || "this")
        title = signal["title"].to_s.strip.truncate(120).presence or return
        page_title = RISK_PAGE.fetch(I18n.locale.to_s, RISK_PAGE["en"])
        page = project.wiki.find_page(page_title)
        return if page && Assistant::Text.overlap(page.text.to_s, title).first >= 0.7

        line = "- #{wp ? "##{wp.id} " : ''}#{title} — “#{signal['quote']}”（#{speaker&.name || '–'}，#{day(stated_on)}）"
        text = [page&.text.presence || "# #{page_title}\n", line].join("\n")
        offer(signal, kind: "said_risk", subject: wp || project, decider: wp ? decider_for(wp) : leads.first,
                      title: I18n.t("assistant.understanding.signals.risk", title:),
                      steps: [{ "op" => "create_wiki_page",
                                "attributes" => { "project_id" => project.id, "title" => page_title, "text" => text,
                                                  "notes" => I18n.t("assistant.understanding.signals.risk_note", title: title.truncate(60)) } }],
                      extra: wp ? [I18n.t("assistant.understanding.signals.risk_why", ref: "##{wp.id}")] : [])
      end

      # A term goes into the team's glossary, which the editor's writing then
      # follows (G3).
      def knowledge(signal)
        return unless project.wiki

        term = signal["term"].to_s.strip.truncate(80).presence or return
        explanation = signal["explanation"].to_s.strip.truncate(300).presence or return
        page_title = Assistant::Writing::GLOSSARY_TITLES.lazy.filter_map { project.wiki.find_page(it)&.title }.first ||
                     GLOSSARY_PAGE.fetch(I18n.locale.to_s, GLOSSARY_PAGE["en"])
        page = project.wiki.find_page(page_title)
        return if page&.text.to_s.match?(/^\s*[-*]\s*\*\*#{Regexp.escape(term)}\*\*/)

        text = [page&.text.presence || "# #{page_title}\n", "- **#{term}**：#{explanation}"].join("\n")
        offer(signal, kind: "said_knowledge", subject: project, decider: speaker || leads.first,
                      title: I18n.t("assistant.understanding.signals.knowledge", term:),
                      steps: [{ "op" => "create_wiki_page",
                                "attributes" => { "project_id" => project.id, "title" => page_title, "text" => text,
                                                  "notes" => I18n.t("assistant.understanding.signals.knowledge_note", term:) } }])
      end

      def offer(signal, kind:, subject:, decider:, title:, steps:, extra: [])
        return unless decider.is_a?(User) && decider.active? && !decider.is_a?(AssistantUser)
        return if Assistant::Signal.silenced?(kind, recipient: decider, project:)
        return if Assistant::Action.where(kind:).where("basis @> ?", [{ gid: source.to_gid.to_s }].to_json)
                                   .where("plan->'steps' = ?::jsonb", steps.to_json).exists?

        action = Assistant::Actions::Propose.call(
          kind:, title:, steps:, on_behalf_of: decider, project:, subject:, auto_execute: own?(kind, decider),
          basis: [Assistant::Basis.for(source, quote: signal["quote"])]
        )
        return action unless action.proposed?

        Assistant::Signal.offer!(
          detector: kind, fingerprint: "#{source.to_gid}|#{Digest::SHA1.hexdigest(steps.to_json)[0, 12]}", recipient: decider,
          project:, subject:, action:, channel: "brief", state: "pending", score: 30, deliver_at: Time.current,
          payload: { "headline" => title, "because" => ["“#{signal['quote']}”", *extra], "nature" => "decision",
                     "options" => [{ "label" => I18n.t("assistant.understanding.signals.accept"), "action_id" => action.id }],
                     "source_gid" => source.to_gid.to_s }
        )
        action
      rescue ActiveRecord::RecordNotUnique
        action
      end

      # Someone's own time is theirs to state: logged at once, undoable.
      def own?(kind, decider) = kind.in?(%w[said_time_spent said_time_off]) && decider == speaker

      def decider_for(wp)
        return speaker if speaker&.allowed_in_work_package?(:edit_work_packages, wp)

        [wp.responsible, wp.assigned_to].find { it.is_a?(User) && it.active? } || leads.first
      end

      def leads = Assistant::Proactive::Routing.leads(project)

      def date(value)
        return unless value.is_a?(Hash)

        Assistant::Understanding::DueResolver.new(project:, stated_on:).call(value.stringify_keys).due_on
      end

      def day(date) = Assistant::Text.day(date)
    end
  end
end
