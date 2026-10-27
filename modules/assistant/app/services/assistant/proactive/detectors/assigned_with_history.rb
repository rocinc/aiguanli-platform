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
  module Proactive
    module Detectors
      # Someone was just made assignee of a work package that already has a
      # past. They get "what you need to know" on the work package itself, the
      # next time they open it: the decisions on record, the questions nobody
      # has answered, and who knows the work best. Facts only, nothing about
      # how the earlier owner did.
      class AssignedWithHistory < Base
        MIN_COMMENTS = 3
        LISTED = 3

        def candidates
          events("work_package.updated").select do
            it.changed?("assigned_to_id") && it.after("assigned_to_id")
          end.filter_map do |event|
            wp = event.subject
            person = User.find_by(id: event.after("assigned_to_id"))
            next unless wp.is_a?(WorkPackage) && person && human?(person) && event.actor != person

            history = history_of(wp, person)
            next unless history

            candidate(
              fingerprint: "#{wp.id}:#{person.id}", recipient: person, subject: wp, nature: :own, channel: "inline",
              headline: headline(wp, history), because: lines(history), impact: { people: 1 },
              facts: { since: event.created_at }, steps_for: ->(_user) { look_options(wp, history) }
            )
          end
        end

        private

        History = Data.define(:comments, :decisions, :questions, :expert)

        def history_of(wp, person)
          comments = wp.journals.where.not(notes: [nil, ""]).count
          items = Assistant::Intent.visible(person).where(subject: wp).where.not(status: "dismissed").to_a
          decisions = items.select { it.kind == "decision" && it.status == "active" }
          questions = items.select { it.kind == "question" && it.status == "open" }
          return if comments < MIN_COMMENTS && decisions.empty? && questions.empty?

          expert = Assistant::Facts::Expertise.new(project, wp.subject, viewer: person).people(limit: 3).find { it.user != person }
          History.new(comments:, decisions:, questions:, expert:)
        end

        def headline(wp, history)
          facts = [(t("decisions", count: history.decisions.size) if history.decisions.any?),
                   (t("questions", count: history.questions.size) if history.questions.any?)].compact
          facts = facts.any? ? t("has", list: facts.join(t("join"))) : t("thread", count: history.comments)
          return t("headline", ref: "##{wp.id}", facts:) unless history.expert

          with_expert = I18n.t("assistant.proactive.assigned_with_history.headline_expert",
                               ref: "##{wp.id}", facts:, name: history.expert.user.name)
          with_expert.length <= HEADLINE_LIMIT ? with_expert : t("headline", ref: "##{wp.id}", facts:)
        end

        def look_options(wp, history)
          options = [(look("look_decision", history.decisions.first) if history.decisions.any?),
                     (look("look_question", history.questions.first) if history.questions.any?)].compact
          options.presence || [thread_option(wp)]
        end

        def thread_option(wp)
          url = "#{OpenProject::StaticRouting::StaticUrlHelpers.new.work_package_path(wp)}/activity"
          option(t("look_thread"), t("look_thread_consequence"), "look", []).merge(url:)
        end

        def look(key, intent)
          url = Assistant::Provenance.url_for_basis(Assistant::Basis.for(intent.source).to_h)
          option(t(key), t("#{key}_consequence"), "look", []).merge(url:) if url
        end

        def lines(history)
          [*(t("comment_count", count: history.comments) if history.decisions.empty? && history.questions.empty?),
           *history.decisions.first(LISTED).map { t("decision", title: it.title, by: it.owner&.name || "–") },
           *history.questions.first(LISTED).map { t("question", title: it.title, by: it.owner&.name || "–") },
           *(t("knows", name: history.expert.user.name, evidence: history.expert.evidence.first) if history.expert)]
        end
      end
    end
  end
end
