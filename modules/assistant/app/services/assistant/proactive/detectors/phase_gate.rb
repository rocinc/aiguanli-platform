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
      # Two weeks before a phase gate (04 E2): is the phase ready to be left?
      # Work still open in it, past its date or nobody on it, and how far its
      # planned finish runs past the gate. Told to whoever leads, with the
      # work that will not make it offered to the next phase.
      class PhaseGate < Base
        WORKING_DAYS_BEFORE = 10

        def candidates
          project.phases.active.includes(:definition).flat_map do |phase|
            gate = gate_date(phase) or next []
            left = Assistant::Facts.working_days_between(today + 1, gate)
            next [] unless left == WORKING_DAYS_BEFORE

            work = WorkPackage.where(project:, project_phase_definition_id: phase.definition_id)
                              .includes(:status, :assigned_to).to_a
            open = work.select { Assistant::Facts.open?(it) }
            leads.map { build(phase, gate, work, open, it) }
          end
        end

        private

        # The gate this phase is heading to: its finish gate, or the next phase's start gate.
        def gate_date(phase)
          return phase.finish_date if phase.finish_gate? && phase.finish_date
          return unless phase.finish_date

          following = project.phases.active.includes(:definition).select { it.position > phase.position }.min_by(&:position)
          following&.start_gate? ? (following.start_date || phase.finish_date) : phase.finish_date
        end

        def build(phase, gate, work, open, lead)
          overdue = open.select { it.due_date && it.due_date < today }
          nobody = open.reject(&:assigned_to_id)
          finish = open.filter_map(&:due_date).max
          slip = finish && finish > gate ? Assistant::Facts.working_days_between(gate + 1, finish) : 0
          problems = overdue.size + nobody.size + slip
          candidate(
            fingerprint: "#{phase.id}:#{gate}", recipient: lead, subject: project, nature: :team,
            channel: problems.zero? ? "brief" : nil,
            headline: t(problems.zero? ? "clean" : "headline", phase: phase.name, date: day(gate), open: open.size),
            because: [t("done", done: work.size - open.size, total: work.size),
                      (t("overdue", list: refs(overdue)) if overdue.any?),
                      (t("nobody", list: refs(nobody)) if nobody.any?),
                      (t("slip", days: slip, finish: day(finish)) if slip.positive?)].compact,
            impact: { deadline: slip.positive?, cascade: open.size, people: open.filter_map(&:assigned_to_id).uniq.size },
            act_by: gate, effort_days: 2, facts: { phase_id: phase.id, gate:, open: open.size, slip: },
            steps_for: ->(user) { options(phase, gate, open, slip) << review_option(phase, gate, work, open, user) }
          )
        end

        def refs(wps) = wps.first(5).map { "##{it.id}" }.join(t("separator"))

        # The gate review material (04 E2 做): one wiki page the team fills in
        # before the gate, with what is done, what is still open and on whom.
        def review_option(phase, gate, work, open, user)
          title, text = OpenProject::LocaleHelper.with_locale_for(user) do
            done = work - open
            [t("review_page", phase: phase.name, date: day(gate)),
             [t("review_intro", phase: phase.name, date: day(gate), done: done.size, total: work.size),
              "", "## #{t('review_done')}", *done.first(30).map { "- ##{it.id} #{it.subject}" },
              "", "## #{t('review_open')}",
              *open.first(30).map { "- ##{it.id} #{it.subject} (#{it.assigned_to&.name || '–'}, #{day(it.due_date) || '–'})" },
              "", "## #{t('review_decision')}", "- [ ] #{t('review_pass')}", "- [ ] #{t('review_hold')}"].join("\n")]
          end
          option(t("review"), t("review_consequence"), "gate_review", [wiki_step(title, text, notes: t("review_notes"))])
        end

        def options(phase, gate, open, slip)
          list = []
          following = project.phases.active.includes(:definition).select { it.position > phase.position }.min_by(&:position)
          late = open.select { it.due_date.nil? || it.due_date > gate }
          if following && late.any?
            list << option(t("move_on", count: late.size, phase: following.name), t("move_on_consequence"), "move_to_phase",
                           late.first(5).map { step(it, { "project_phase_definition_id" => following.definition_id }) })
          end
          list
        end
      end
    end
  end
end
