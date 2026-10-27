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
    # Keeps the project's decision record wiki page (scope "title", default
    # from the locale) in step with what was decided: each decision with the
    # exact words, who, when and where, newest first; superseded ones struck
    # through with what replaced them; open objections listed. Written by
    # code from the decisions people recorded, so nothing is invented.
    class DecisionLog < Base
      def self.due?(duty, now = Time.current) = every(duty, now, 1.hour)

      def call
        decisions = Assistant::Intent.where(project:, kind: "decision").where.not(status: "dismissed")
                                      .includes(:owner, :subject, :source, :supersedes).order(stated_at: :desc).to_a
        return Result.nothing("none") if decisions.empty?

        text = render(decisions)
        draft = pending_draft
        page = project.wiki&.find_page(page_title)
        if page && page.text.to_s.strip == text.strip
          withdraw_draft(draft) if draft
          return Result.nothing("unchanged")
        end
        because = [I18n.t("assistant.duties.decision_log.because", count: decisions.size)]
        return append(draft, text, because, decisions.size) if draft

        action = propose(kind: "decision_log", title: I18n.t("assistant.duties.decision_log.title", page: page_title),
                         steps: [step(text)])
        offer(action, headline: action.title, because:)
        Result.new(summary: "#{decisions.size}", action_ids: [action.id], produced: action.proposed?)
      end

      private

      def step(text)
        { "op" => "create_wiki_page",
          "attributes" => { "project_id" => project.id, "title" => page_title, "text" => text,
                            "notes" => I18n.t("assistant.duties.decision_log.notes") } }
      end

      def pending_draft
        Assistant::Action.proposed.where(kind: "decision_log", project:, on_behalf_of: delegator)
                         .where("basis @> ?", [{ gid: duty.to_gid.to_s }].to_json).order(:id)
                         .detect { it.steps.first&.dig("attributes", "title") == page_title }
      end

      def append(draft, text, because, count)
        steps = Assistant::Actions::SourceNote.apply([step(text).deep_stringify_keys], draft.basis)
        preview = Assistant::Actions::Preview.new(steps:, user: delegator).call
        return Result.nothing("preview_failed") unless preview.success

        draft.update!(plan: draft.plan.merge("steps" => steps), preview: preview.to_h)
        Assistant::Signal.live.where(action: draft, detector: "duty_decision_log").find_each do |signal|
          signal.update!(payload: signal.payload.merge("because" => because))
        end
        Result.new(summary: "#{count}", action_ids: [draft.id], produced: true)
      end

      def withdraw_draft(draft)
        Assistant::Signal.live.where(action: draft, detector: "duty_decision_log").find_each { it.settle!("resolved") }
        withdraw(draft)
      end

      def page_title = Assistant::DecisionRecord.title(project)

      def render(decisions)
        active, past = decisions.partition { _1.status == "active" }
        lines = ["# #{page_title}", "", I18n.t("assistant.duties.decision_log.intro"), ""]
        lines << "## #{I18n.t('assistant.duties.decision_log.active')}" << ""
        active.each { lines.concat(entry(_1)) }
        if past.any?
          lines << "## #{I18n.t('assistant.duties.decision_log.superseded')}" << ""
          past.each { lines.concat(entry(_1, struck: true)) }
        end
        lines.join("\n")
      end

      def entry(item, struck: false)
        title = struck ? "~~#{item.title}~~" : item.title
        where = item.subject.is_a?(WorkPackage) ? "##{item.subject_id}" : item.subject.try(:title).to_s
        lines = ["### #{title}",
                 "> #{item.quote}",
                 "",
                 I18n.t("assistant.duties.decision_log.meta", by: item.owner&.name || "–", on: l(item.stated_at.to_date), where:)]
        replacement = Assistant::Intent.find_by(supersedes_id: item.id)
        lines << I18n.t("assistant.duties.decision_log.replaced_by", title: replacement.title) if replacement
        objections = item.open_objections.includes(:owner).to_a
        objections.each { lines << "- #{I18n.t('assistant.duties.decision_log.objection', name: _1.owner&.name || '–', quote: _1.quote)}" }
        lines << ""
      end
    end
  end
end
