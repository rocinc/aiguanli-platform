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
  # What a meeting should open with (04 S6.1): what the last one left
  # unfinished, what is due or late among the people invited, and questions
  # still waiting for an answer. Facts about things, not a tally of people:
  # a name appears only where it is the reader's own.
  class MeetingRecap
    Entry = Data.define(:section, :title, :line, :url, :work_package_id, :late, :intent)

    LIMITS = { last_time: 3, due: 2, questions: 2 }.freeze
    TOTAL = 5
    DUE_WORKING_DAYS = 5
    OLDER_LIMIT = 6

    def initialize(meeting, user, today: Date.current, shared: false)
      @meeting = meeting
      @user = user
      @today = today
      @shared = shared
    end

    attr_reader :meeting, :user, :today

    def sections
      @sections ||= trim(last_time:, due: due.first(LIMITS.fetch(:due)), questions:)
    end

    def older_due = due.drop(LIMITS.fetch(:due)).first(OLDER_LIMIT)

    def older_late? = older_due.all? { it.late }

    def entries = sections.values.flatten

    def landed = (last_time && @landed).to_i

    def previous
      return @previous if defined?(@previous)

      @previous = retro? ? previous_retro : said.previous_meeting(meeting)
    end

    def shared? = @shared

    def retro? = meeting.title.to_s.match?(Assistant::Proactive::Detectors::CrossSprintPattern::RETRO)

    private

    def said = @said ||= Assistant::Said.new(user, today:)

    def project = meeting.project

    def people = @people ||= meeting.participants.includes(:user).filter_map(&:user).select(&:active?)

    def covered
      @covered ||= meeting.agenda_items.map { "#{it.title} #{Assistant::Text.plain(it.notes)}" }.join(" ")
    end

    def agenda_work_package_ids = @agenda_work_package_ids ||= meeting.agenda_items.filter_map(&:work_package_id).to_set

    def mentioned?(title) = covered.include?(title.to_s.first(12))

    def trim(all)
      budget = TOTAL
      all.to_h do |key, list|
        take = list.first([LIMITS.fetch(key), budget].min)
        budget -= take.size
        [key, take]
      end
    end

    def last_time
      @last_time ||= begin
        @landed = 0
        items = previous ? said_items : []
        items.filter_map { last_time_entry(it) }.sort_by(&:first).map(&:last).reject { mentioned?(it.title) }
      end
    end

    def said_items
      said.visible.where(subject: previous, kind: %w[commitment deferral question decision])
          .where(status: Assistant::Intent::LIVE_STATUSES).includes(:owner, :work_package).order(:stated_at).to_a
    end

    def last_time_entry(item)
      return if item.kind == "decision" && item.answered_by_id

      work_package = item.work_package
      if work_package && !Assistant::Facts.open?(work_package)
        @landed += 1
        return
      end

      [rank(item, work_package), Entry.new(section: :last_time, title: item.title, line: last_time_line(item, work_package),
                                           url: last_time_url(work_package), work_package_id: work_package&.id, late: false, intent: item)]
    end

    def rank(item, work_package)
      return [2, item.stated_at.to_i] if item.kind == "decision"

      late = item.overdue?(today) || (work_package&.due_date.present? && work_package.due_date < today)
      [late ? 0 : 1, item.stated_at.to_i]
    end

    def last_time_line(item, work_package)
      title = item.title.truncate(80)
      state = if work_package then work_package_state(work_package)
              elsif item.kind == "question" then t("question_waiting", days: (today - item.stated_at.to_date).to_i)
              elsif item.kind == "decision" then t("decision_stands")
              else commitment_state(item)
              end
      t("said", title:, state:)
    end

    def commitment_state(item)
      return t("unclaimed") if item.owner.nil?

      key = !@shared && item.owner == user ? "yours" : "open"
      return t(key) unless item.said_due_on

      t("#{key}_dated", date: Assistant::Text.day(item.said_due_on))
    end

    def work_package_state(work_package)
      state = "##{work_package.id} #{work_package.status.name}"
      return state unless work_package.due_date

      due = Assistant::Text.day(work_package.due_date)
      work_package.due_date < today ? t("late_state", state:, date: due) : t("due_state", state:, date: due)
    end

    def last_time_url(work_package)
      return routes.work_package_path(work_package) if work_package

      routes.meeting_path(previous)
    end

    def due
      @due ||= begin
        horizon = Assistant::Facts.add_working_days(today, DUE_WORKING_DAYS)
        ids = people.map(&:id)
        WorkPackage.visible(user).where(project:, assigned_to_id: ids).where.not(status_id: Assistant::Facts.closed_status_ids)
                   .where(due_date: ..horizon).where.not(id: agenda_work_package_ids.to_a).order(due_date: :desc, id: :asc).limit(30).to_a
                   .reject { covered.include?("##{it.id}") }.sort_by { soonest_first(it) }.map { due_entry(it) }
      end
    end

    def soonest_first(work_package)
      work_package.due_date < today ? [1, -work_package.due_date.jd] : [0, work_package.due_date.jd]
    end

    def due_entry(work_package)
      key = work_package.due_date < today ? "late" : "due"
      line = t(key, ref: "##{work_package.id}", subject: work_package.subject.truncate(40),
                    date: Assistant::Text.day(work_package.due_date))
      Entry.new(section: :due, title: work_package.subject, line:, url: routes.work_package_path(work_package),
                work_package_id: work_package.id, late: work_package.due_date < today, intent: nil)
    end

    def questions
      @questions ||= said.visible.where(project:, kind: "question", status: "open", counterparty_id: people.map(&:id))
                         .where(stated_at: ..1.day.ago).includes(:subject).order(:stated_at).limit(6).to_a
                         .reject { mentioned?(it.title) }.map { question_entry(it) }
    end

    def question_entry(item)
      key = !@shared && item.counterparty_id == user.id ? "question_for_you" : "question"
      line = t(key, title: item.title.truncate(60), days: (today - item.stated_at.to_date).to_i)
      Entry.new(section: :questions, title: item.title, line:, url: subject_url(item.subject), work_package_id: nil, late: false,
                intent: item)
    end

    def subject_url(subject)
      case subject
      when WorkPackage then routes.work_package_path(subject)
      when Meeting then routes.meeting_path(subject)
      end
    end

    def previous_retro
      ::Meeting.where(project:, template: false).where(start_time: ...meeting.start_time).order(start_time: :desc)
               .detect { it.title.to_s.match?(Assistant::Proactive::Detectors::CrossSprintPattern::RETRO) }
    end

    def routes = Rails.application.routes.url_helpers

    def t(key, **) = I18n.t("assistant.meeting_recap.#{key}", **)
  end
end
