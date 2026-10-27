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
  # A person's day (H1): what waits for their decision, what is written and
  # waits to be sent, what the assistant did for them, and, after an absence,
  # what happened meanwhile. What does not fit the caps goes to "deferred".
  # Read live off signals and actions; the order is stable between requests.
  class Brief
    DECISIONS = 3
    DRAFTS = 3
    DONE = 5
    DONE_WINDOW = 24.hours
    NEWCOMER_DAYS = 7
    LINE_SUBJECTS = %w[WorkPackage Version WikiPage Message Project Budget Sprint Meeting].freeze

    def initialize(user:, project: nil, now: Time.current)
      @user = user
      @project = project
      @now = now
    end

    attr_reader :user, :project, :now

    def decisions = decision_signals.first(DECISIONS)

    # Signals the person dealt with from the page or an aside stay in the day's
    # note, struck through, for as long as a stale notice lingers.
    def handled
      @handled ||= begin
        scope = Assistant::Signal.where(recipient: user, outcome: %w[adopted edited], channel: %w[brief notification],
                                        deliver_at: ..@now, outcome_at: (@now - Assistant::Signal::STALE_LINGERS)..)
        scope = scope.where(project:) if project
        scope.includes(:subject, :action, :project).to_a.select { visible?(it) && !it.payload["pooled"] && !told_on_page?(it) }
      end
    end

    def decision_lines
      @decision_lines ||= [*decisions, *handled].sort_by { [-it.score.to_f, -it.created_at.to_f, -it.id] }
    end

    def drafts = draft_items.first(DRAFTS)

    def done
      @done ||= Assistant::Action.where(status: "executed", executed_at: (@now - DONE_WINDOW)..)
                                 .merge(for_me_or_welcoming_me)
                                 .where(project_scope).includes(:on_behalf_of, :decided_by, :project)
                                 .order(executed_at: :desc, id: :desc).limit(DONE).to_a
    end

    def deferred = [*decision_signals.drop(DECISIONS), *draft_items.drop(DRAFTS)]

    def away
      return if Assistant::Signal.silenced?("away_digest", recipient: user, project:)

      @away ||= Assistant::Away.new(user:, project:, now: @now).to_h.presence
    end

    def empty? = decisions.empty? && drafts.empty? && done.empty?

    def newcomer?
      joined = Member.where(principal: user).minimum(:created_at)
      joined.present? && joined > @now - NEWCOMER_DAYS.days
    end

    def multiple_projects?
      @multiple_projects ||= Project.active.allowed_to(user, :use_assistant).limit(2).many?
    end

    def day = Assistant::Text.day(today)

    def today = @now.in_time_zone(user.time_zone || Time.zone).to_date

    private

    def signals
      @signals ||= begin
        scope = Assistant::Signal.live.where(recipient: user).where.not(channel: "inline")
                                 .where(deliver_at: ..@now).where(snoozed_until: [nil, ..@now])
        scope = scope.where(project:) if project
        scope.includes(:subject, :action, :project).order(score: :desc, created_at: :desc, id: :desc).to_a
             .select { visible?(it) && !it.payload["pooled"] && !told_on_page?(it) && !shown_inline?(it) }
      end
    end

    def inline_twins
      @inline_twins ||= begin
        scope = Assistant::Signal.live.where(recipient: user, channel: "inline")
        scope = scope.where(project:) if project
        scope.pluck(:detector, :subject_type, :subject_id, Arel.sql("payload ->> 'headline'")).to_set
      end
    end

    def shown_inline?(signal)
      signal.channel == "brief" &&
        inline_twins.include?([signal.detector, signal.subject_type, signal.subject_id, signal.payload["headline"]])
    end

    def drafting = @drafting ||= Assistant::Drafts.new(user:, signals:, project:, now: @now)

    def draft_items = drafting.items

    def decision_signals = @decision_signals ||= signals.reject { drafting.signal_ids.include?(it.id) }

    # The onboarding page is the delegator's to publish, and the newcomer's to
    # find waiting (06 M9).
    def for_me_or_welcoming_me
      Assistant::Action.where(on_behalf_of: user)
                       .or(Assistant::Action.where(kind: Assistant::Duties::Onboarding::KIND, subject: user))
    end

    def project_scope = project ? { project_id: project.id } : {}

    def told_on_page?(signal)
      signal.channel == "notification" && signal.subject.class.name.in?(LINE_SUBJECTS)
    end

    def visible?(signal)
      subject = signal.subject
      return true if subject.nil?
      return subject.visible?(user) if subject.respond_to?(:visible?) && subject.method(:visible?).arity != 0

      true
    end
  end
end
