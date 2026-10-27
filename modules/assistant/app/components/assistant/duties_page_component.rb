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
  # The jobs handed to the assistant, read like a handover note: one card per
  # duty says what it does, for whom, how often, how far it may go on its own,
  # what it did last and when it runs next. Anyone who may use the assistant
  # here can read it; only the person who handed a duty over, and the project's
  # managers, can change it.
  class DutiesPageComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    ID = "assistant-duties-page"
    GRANT_WINDOW = 90.days
    WEEKDAYS = (1..5)
    HOURS = (6..20)
    DIRECT_KINDS = %w[decision_log advance_merged_pr].freeze

    def self.decided_t2(project)
      Assistant::Action.where(project:, tier: "t2").where.not(decided_by_id: nil)
                       .where(status: %w[executed rejected undone]).where(created_at: GRANT_WINDOW.ago..)
    end

    # Only kinds the team has actually been asked about here can be granted:
    # a grant always names something people have seen.
    def self.grantable_kinds(project) = decided_t2(project).distinct.pluck(:kind)

    def self.kind_label(kind)
      I18n.t("assistant.grants.kinds.#{kind}", default: kind.to_s.humanize)
    end

    def initialize(project:, user:, read_only: false)
      super()
      @project = project
      @user = user
      @read_only = read_only
    end

    attr_reader :project, :user

    def read_only? = @read_only

    def manager? = !read_only? && user.allowed_in_project?(:manage_assistant, project)

    def operable?(duty) = !read_only? && (duty.delegator_id == user.id || manager?)

    def duties = @duties ||= Assistant::Duty.where(project:).includes(:delegator).order(:created_at).to_a

    def open_kinds
      settings = Assistant::Proactive::ProjectSettings.for(project)
      (Assistant::Duty::KINDS - duties.map(&:kind)).select { settings.duty_allowed?(it) }
    end

    # A kind added before its copy shows its name instead of breaking the page.
    def title(kind) = t("assistant.duties.kinds.#{kind}.title", default: kind.to_s.humanize)

    def description(kind) = t("assistant.duties_page.kinds.#{kind}.does", default: "")

    def will_not(kind) = t("assistant.duties_page.kinds.#{kind}.wont", default: "")

    def default_level(kind) = t("assistant.duties_page.kinds.#{kind}.level", default: t("assistant.common.no_value"))

    def level(duty)
      draft_only?(duty) ? t("assistant.duties_page.level_draft") : default_level(duty.kind)
    end

    def draft_only?(duty) = DIRECT_KINDS.include?(duty.kind) && Assistant::DutyScope.ceiling(duty) == "draft"

    def dom_id(duty) = "assistant-duty-#{duty.kind.dasherize}"

    def delegator_name(duty) = duty.delegator_id == user.id ? t("assistant.duties_page.delegated_by_you") : duty.delegator.name

    def schedule(duty)
      scope = duty.scope.to_h
      case duty.kind
      when "weekly_status"
        t("assistant.duties_page.schedule.weekly_status", day: weekday((scope["wday"] || 5).to_i),
                                                          hour: hour_label((scope["hour"] || 16).to_i))
      else t("assistant.duties_page.schedule.#{duty.kind}", default: "")
      end
    end

    def scope_text(duty)
      key = "assistant.duties_page.kinds.#{duty.kind}.scope"
      case duty.kind
      when "release_watch" then t(key, version: watched_version(duty)&.name || t("assistant.duties_page.next_version"))
      when "decision_log" then t(key, page: duty.scope.to_h["title"].presence || t("assistant.duties.decision_log.page_title"))
      when "advance_merged_pr" then target_status_text(duty, key)
      else t(key, default: t("assistant.common.no_value"))
      end
    end

    def weekday(wday) = I18n.t("date.abbr_day_names")[wday % 7]

    def hour_label(hour)
      part = case hour
             when 0...12 then t("assistant.duties_page.hours.morning")
             when 12 then t("assistant.duties_page.hours.noon")
             when 13...18 then t("assistant.duties_page.hours.afternoon")
             else t("assistant.duties_page.hours.evening")
             end
      t("assistant.duties_page.hours.at", part:, hour: hour > 12 ? hour - 12 : hour)
    end

    def watched_version(duty)
      id = duty.scope.to_h["version_id"]
      id.present? ? open_versions.find { it.id == id.to_i } : nil
    end

    def open_versions = @open_versions ||= project.shared_versions.where(status: "open").order(:effective_date, :name).to_a

    def statuses = @statuses ||= Status.order(:position).to_a

    def wiki_titles = @wiki_titles ||= project.wiki ? project.wiki.pages.order(:title).pluck(:title) : []

    def last_run(duty)
      return t("assistant.duties_page.never_ran") if duty.last_run_at.nil?

      stamp = Assistant::Text.moment(duty.last_run_at)
      actions = last_actions(duty)
      return t("assistant.duties_page.last_actions", when: stamp) if actions.any?

      if duty.last_result.to_h["produced"]
        t("assistant.duties_page.last_done", when: stamp)
      else
        t("assistant.duties_page.last_nothing", when: stamp, why: nothing_reason(duty))
      end
    end

    def last_actions(duty)
      @last_actions ||= {}
      @last_actions[duty.id] ||= Assistant::Action.where(id: Array(duty.last_result.to_h["action_ids"])).order(:id).to_a
                                                  .select { it.visible_to?(user) }
    end

    def linkable_actions(duty) = duty.kind == "timesheet_draft" ? [] : last_actions(duty).first(2)

    def more_actions(duty) = last_actions(duty).size - linkable_actions(duty).size

    def action_path(action) = url_helpers.assistant_action_path(action)

    def next_run(duty)
      return t("assistant.duties_page.next_paused") unless duty.active?

      moment = Assistant::Duties::NextRun.call(duty)
      return Assistant::Text.moment(moment) if moment

      t("assistant.duties_page.kinds.#{duty.kind}.next_none", default: t("assistant.duties_page.next_none"))
    end

    def stale?(duty) = duty.active? && duty.stale?

    def stale_text(duty)
      what = t("assistant.duties_page.kinds.#{duty.kind}.output", default: t("assistant.duties_page.output"))
      t("assistant.duties_page.stale", count: duty.unseen_runs, what:)
    end

    def scope_fields(duty) = Assistant::DutyScope.fields(duty.kind)

    def scope_value(duty, field) = duty.scope.to_h[field]

    def hours = HOURS

    def duty_path(duty) = url_helpers.project_assistant_duty_path(project, duty)

    def create_path = url_helpers.project_assistant_duties_path(project)

    def grants = @grants ||= Assistant::Grant.live.where(project:).includes(:granted_by).order(:created_at).to_a

    def grant_candidates
      granted = grants.map(&:action_kind)
      decided_counts.keys.map(&:first).uniq.reject { granted.include?(it) }.sort_by { -confirmed(it) }
    end

    def confirmed(kind) = decided_counts.select { |(k, status), _| k == kind && status == "executed" }.values.sum

    def declined(kind) = decided_counts.select { |(k, status), _| k == kind && status != "executed" }.values.sum

    def example(kind)
      @examples ||= self.class.decided_t2(project).order(created_at: :desc).pluck(:kind, :title)
                        .each_with_object({}) { |(k, title), map| map[k] ||= title }
      @examples[kind]
    end

    delegate :kind_label, to: :class

    def grants_path = url_helpers.project_assistant_grants_path(project)

    def grant_path(grant) = url_helpers.project_assistant_grant_path(project, grant)

    def granted_line(grant)
      t("assistant.grants.granted_by", name: grant.granted_by.name, date: Assistant::Text.day(grant.created_at.to_date))
    end

    private

    def target_status_text(duty, key)
      status = statuses.find { it.id == duty.scope.to_h["status_id"].to_i }
      status ? t(key, status: status.name) : t("assistant.duties_page.kinds.advance_merged_pr.scope_auto")
    end

    def nothing_reason(duty)
      summary = duty.last_result.to_h["summary"].to_s
      return t("assistant.duties_page.nothing.default") if summary.empty?

      t("assistant.duties_page.nothing.#{summary}", default: t("assistant.duties_page.nothing.default"))
    end

    def decided_counts = @decided_counts ||= self.class.decided_t2(project).group(:kind, :status).count
  end
end
