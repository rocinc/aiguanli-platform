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
  # "While you were away" (06 S5): what others did to your work while you
  # were gone, read straight off the journals so it holds for any history.
  #
  # The absence is the gap between the last two days the person was here,
  # counted in working days and bridged by recorded time off. Under
  # MIN_WORKING_DAYS it is just a weekend and nothing is said.
  class Away
    MIN_WORKING_DAYS = 3
    KEPT_WORKING_DAYS = 3
    WATCHED = %w[due_date start_date assigned_to_id responsible_id status_id target_versions sprint_id priority_id].freeze
    LIMIT = 12
    NAMES = {
      "assigned_to_id" => ->(id) { Principal.find_by(id:)&.name },
      "responsible_id" => ->(id) { Principal.find_by(id:)&.name },
      "status_id" => ->(id) { Status.find_by(id:)&.name },
      "priority_id" => ->(id) { IssuePriority.find_by(id:)&.name },
      "sprint_id" => ->(id) { defined?(::Sprint) ? ::Sprint.find_by(id:)&.name : nil },
      "target_versions" => ->(ids) { Version.where(id: ids.to_s.split(",")).pluck(:name).join(", ").presence }
    }.freeze

    Period = Data.define(:from, :to, :working_days)

    def initialize(user:, project: nil, now: Time.current)
      @user = user
      @project = project
      @now = now
    end

    attr_reader :user, :project

    def self.mark_present!(user, now: Time.current)
      return unless user.is_a?(User) && user.logged? && !user.is_a?(AssistantUser)

      today = now.in_time_zone(user.time_zone || Time.zone).to_date
      preference = Assistant::Preference.for(user)
      presence = preference.presence.to_h
      return if presence["today"] == today.iso8601

      away = kept_away(user, presence, today, now)
      preference.presence = { "today" => today.iso8601, "before" => presence["today"], "away" => away }.compact
      preference.save!
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # The absence just ended, or the one still shown from an earlier day.
    def self.kept_away(user, presence, today, now)
      before = presence["today"]&.then { Date.iso8601(it) }
      period = before && new(user:, now:).absence_between(before, today)
      return presence["away"] if period.nil? && still_shown?(presence["away"], today)
      return unless period

      { "from" => period.from.iso8601, "to" => period.to.iso8601, "working_days" => period.working_days,
        "until" => Assistant::Facts.add_working_days(today, KEPT_WORKING_DAYS).iso8601 }
    end

    def self.still_shown?(away, today) = away.present? && Date.iso8601(away["until"]) >= today

    def period
      return @period if defined?(@period)

      @period = stored_period || pause_period
    end

    def absence_between(before, back) = build_period(before, back)

    def away? = period.present?

    def to_h
      return {} unless away?

      { "from" => period.from.iso8601, "to" => period.to.iso8601, "working_days" => period.working_days,
        "changed" => changed, "reassigned" => reassigned, "asked" => asked, "promised" => promised }
    end

    private

    def today = @now.in_time_zone(user.time_zone || Time.zone).to_date

    def stored_period
      stored = Assistant::Preference.find_by(owner: user)&.presence.to_h["away"]
      return unless self.class.still_shown?(stored, today)

      Period.new(from: Date.iso8601(stored["from"]), to: Date.iso8601(stored["to"]), working_days: stored["working_days"])
    end

    # Reminders paused from the account settings and now over.
    def pause_period
      pause = user.pref.pause_reminders
      return unless ActiveRecord::Type::Boolean.new.cast(pause["enabled"]) && pause["first_day"].present? && pause["last_day"].present?

      from = Date.parse(pause["first_day"].to_s)
      to = Date.parse(pause["last_day"].to_s)
      return unless to < today && today <= Assistant::Facts.add_working_days(to, KEPT_WORKING_DAYS)

      Period.new(from:, to:, working_days: Assistant::Facts.working_days_between(from, to))
    end

    def build_period(before, back)
      from = before + 1
      to = back - 1
      return if to < from

      days = (from..to).count { Assistant::Facts.working_day?(it) && !time_off?(it) }
      off = (from..to).count { Assistant::Facts.working_day?(it) && time_off?(it) }
      return if days + off < MIN_WORKING_DAYS

      Period.new(from:, to:, working_days: days + off)
    end

    def time_off?(date) = time_off.any? { it.cover?(date) }

    def time_off
      @time_off ||= UserNonWorkingTime.where(user:).pluck(:start_date, :end_date).map { |from, to| from..to }
    end

    def window = period.from.beginning_of_day..@now

    # Journals by someone else on work packages this person is assigned to or
    # responsible for, or was before the change.
    def journals
      @journals ||= begin
        mine = WorkPackage.visible(user).where("assigned_to_id = :id OR responsible_id = :id", id: user.id)
        mine = mine.where(project:) if project
        ids = mine.pluck(:id) | handed_away_ids
        Journal.where(journable_type: "WorkPackage", journable_id: ids, created_at: window)
               .where.not(user_id: user.id).where("version > 1").includes(:user, :journable).order(:created_at).to_a
      end
    end

    # Work taken off this person: some journal in the window has a
    # predecessor that still named them.
    def handed_away_ids
      touched = Journal.where(journable_type: "WorkPackage", created_at: window).where.not(user_id: user.id)
                       .where("version > 1")
      previous = Journal.joins("JOIN work_package_journals ON work_package_journals.id = journals.data_id")
                        .where(journable_type: "WorkPackage")
                        .where("journals.journable_id = touched.journable_id AND journals.version = touched.version - 1")
                        .where("work_package_journals.assigned_to_id = :id OR work_package_journals.responsible_id = :id",
                               id: user.id)
      ids = Journal.from(touched, :touched).where("EXISTS (#{previous.to_sql})").distinct.pluck("touched.journable_id")
      scope = WorkPackage.visible(user).where(id: ids)
      scope = scope.where(project:) if project
      scope.pluck(:id)
    end

    def changed
      changes_by_package.values.filter_map do |entry|
        changes = entry[:changes].except(*handed_fields(entry)).reject { |_, (before, after)| before == after }
        next if changes.empty?

        package_item(entry, changes.map { |field, (before, after)| change_line(field, before, after) })
      end.first(LIMIT)
    end

    def reassigned
      changes_by_package.values.filter_map do |entry|
        fields = handed_fields(entry)
        next if fields.empty?

        package_item(entry, fields.map { |field| handed_line(field, entry[:changes][field].last) })
      end.first(LIMIT)
    end

    # What this person promised, and when it now stands, so a moved date is
    # noticed before the person waiting asks.
    def promised

      scope = Assistant::Said.new(user, today:).mine.where.not(said_due_on: nil)
                             .where(stated_at: ...today.in_time_zone(user.time_zone || Time.zone))
      scope = scope.where(project:) if project
      scope.limit(5).map do |item|
        { "headline" => I18n.t("assistant.away.promised", name: item.counterparty&.name || I18n.t("assistant.away.someone"),
                                                          title: item.title.truncate(60), date: date(item.said_due_on)),
          "because" => ["“#{item.quote.to_s.truncate(80)}”"].reject { it == "“”" },
          "subject" => subject_ref(item.subject), "at" => item.stated_at.iso8601 }
      end
    end

    # Questions put to this person that are still open, oldest first, with how
    # long each has waited.
    def asked

      scope = Assistant::Said.new(user, today:).questions_for_me
      scope = scope.where(project:) if project
      scope.limit(5).map do |item|
        days = Assistant::Facts.working_days_between(item.stated_at.to_date, today - 1)
        { "headline" => I18n.t("assistant.away.asked", name: item.owner&.name || I18n.t("assistant.away.someone"),
                                                       title: item.title.truncate(60)),
          "because" => [I18n.t("assistant.away.waited", count: days)],
          "subject" => subject_ref(item.subject), "at" => item.stated_at.iso8601 }
      end
    end

    def handed_fields(entry)
      %w[assigned_to_id responsible_id].select do |field|
        before, after = entry[:changes][field]
        before == user.id && after != user.id
      end
    end

    def package_item(entry, lines)
      journal = entry[:journals].last
      wp = entry[:work_package]
      { "headline" => I18n.t("assistant.away.changed", ref: "##{wp.id} #{wp.subject.truncate(50)}", who: who(entry[:journals])),
        "because" => lines + basis_lines(entry[:journals]),
        "subject" => subject_ref(wp), "at" => journal.created_at.iso8601 }
    end

    def who(journals)
      journals.map { actor(it) }.uniq.to_sentence(two_words_connector: I18n.t("assistant.card.and"),
                                                  words_connector: I18n.t("assistant.card.separator"),
                                                  last_word_connector: I18n.t("assistant.card.and"))
    end

    def actor(journal)
      cause = journal.cause.to_h
      return journal.user&.name || I18n.t("assistant.away.someone") unless cause["type"] == "assistant_action"

      behalf = User.find_by(id: cause["on_behalf_of_id"])
      behalf ? I18n.t("assistant.away.on_behalf", user: behalf.name) : AssistantUser.instance.name
    end

    def basis_lines(journals)
      journals.filter_map { it.cause.to_h.dig("basis", "label") }.uniq.map { I18n.t("assistant.away.basis", basis: it) }
    end

    def change_line(field, before, after)
      I18n.t("assistant.away.change", field: WorkPackage.human_attribute_name(field.to_s.delete_suffix("_id")),
                                      before: shown(field, before), after: shown(field, after))
    end

    def handed_line(field, person_id)
      key = field == "assigned_to_id" ? "assignee" : "responsible"
      I18n.t("assistant.away.handed.#{key}", name: shown(field, person_id))
    end

    def shown(field, value)
      return I18n.t("assistant.card.empty_value") if value.blank?
      return date(value.is_a?(Date) ? value : Date.parse(value.to_s)) if field.in?(%w[due_date start_date])

      NAMES[field]&.call(value) || value.to_s
    end

    def date(value) = Assistant::Text.day(value)

    def subject_ref(record)
      return unless record.is_a?(WorkPackage)

      { "type" => "WorkPackage", "id" => record.id, "label" => "##{record.id} #{record.subject}", "project" => record.project.name,
        "url" => OpenProject::StaticRouting::StaticUrlHelpers.new.work_package_path(record) }
    end

    def changes_by_package
      @changes_by_package ||= journals.each_with_object({}) do |journal, acc|
        changed = journal.get_changes.stringify_keys.slice(*WATCHED)
        next if changed.empty?

        entry = acc[journal.journable_id] ||= { work_package: journal.journable, changes: {}, journals: [] }
        changed.each do |field, (before, after)|
          entry[:changes][field] = [entry[:changes].dig(field, 0) || before, after]
        end
        entry[:journals] << journal
      end
    end
  end
end
