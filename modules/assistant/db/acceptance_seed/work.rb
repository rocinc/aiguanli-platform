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

module AssistantSeed
  class Work
    STARTED = %i[doing devdone testing closed].freeze
    TRIAGE_STATUSES = %i[clarifying clear confirmed backlog planned].freeze

    def initialize(ctx)
      @ctx = ctx
      @rows = WORK_PACKAGE_ROWS.index_by { it[:id] }
    end

    def call
      ordered.each { |row| run(row, timeline(row)) }
      relations
      derive_parents
      reset_sequence
      verify
    end

    private

    def project = @ctx.project

    def ordered = @rows.values.sort_by { [depth(it), it[:id]] }

    def depth(row) = row[:par] ? 1 + depth(@rows.fetch(row[:par])) : 0

    def sprint_ids = @sprint_ids ||= Sprint.where(project:).to_h { [it.name[/\d+/].to_i, it.id] }

    def planner(row) = %i[epic story feature].include?(row[:ty]) ? :ada : :sam

    def worker(row) = REASSIGNED_TODAY[row[:id]] || row[:who]

    def timeline(row)
      steps = [creation(row)]
      steps << triage(row) if triage?(row)
      steps << hold(row) if row[:st] == :onhold
      steps.concat(progress_steps(row)) if STARTED.include?(row[:st])
      steps.concat(talk_steps(row))
      spread(steps.sort_by { it[:at] })
    end

    def spread(steps)
      steps.each_cons(2) { |before, after| after[:at] = before[:at] + 1.second if after[:at] <= before[:at] }
      steps
    end

    def born(row)
      return @ctx.at(row[:born], "09:10") if row[:born]

      first = row[:s] || -12
      talked = Array(WORK_PACKAGE_TALK[row[:id]]).map(&:first).min
      @ctx.at([first - 9, -14, (talked || first) - 3].min, "09:10")
    end

    def creation(row)
      { at: born(row), who: planner(row), create: true }
    end

    def triage?(row) = row[:who] || row[:s] || row[:ver] || row[:est] || row[:sp] || TRIAGE_STATUSES.include?(row[:st])

    def triage(row)
      stamp = @ctx.at(@ctx.forward(born(row).to_date + 1), "10:05")
      set = { who: worker(row), ver: row[:ver], sprint: row[:sp], est: row[:est], rem: row[:est],
              prio: row[:prio] || :normal }.compact
      if row[:s]
        set[:start] = row[:s]
        set[:due] = row[:d0] || row[:d]
      end
      set[:status] = TRIAGE_STATUSES.include?(row[:st]) ? row[:st] : :planned unless row[:st] == :new
      { at: stamp, who: planner(row), set: }
    end

    def hold(_row) = { at: @ctx.at(-10, "10:30"), who: :sam, set: { status: :onhold } }

    def progress_steps(row)
      return [{ at: @ctx.at(@ctx.forward(born(row).to_date + 5), "09:30"), who: :ada, set: { status: row[:st] } }] unless row[:s]

      steps = []
      est = row[:est]
      rem = row[:rem]
      steps << { at: @ctx.at(row[:s], "09:30"), who: worker(row),
                 set: { status: :doing, rem: (rem if row[:st] == :doing && !later_progress?(row)) || est }.compact }
      steps << { at: progress_time(row), who: worker(row), set: { rem: } } if row[:st] == :doing && later_progress?(row)
      case row[:st]
      when :devdone then steps << { at: @ctx.at(-3, "17:30"), who: worker(row), set: { status: :devdone, rem: 0 } }
      when :testing then steps << { at: test_time(row), who: worker(row), set: { status: :testing, rem: } }
      when :closed then steps.concat(closing_steps(row))
      end
      steps.compact
    end

    def later_progress?(row)
      row[:rem] && row[:est] && row[:rem] < row[:est] && progress_time(row) > @ctx.at(row[:s], "09:30")
    end

    def progress_time(row)
      last = worker(row) == :ben ? @ctx.d(-10) : @ctx.backward(@ctx.d(-1))
      day = @ctx.forward(@ctx.d(row[:s]) + 2)
      @ctx.at([day, last].min, "15:00")
    end

    def test_time(row)
      override = { 79 => [-7, "16:50"] }[row[:id]]
      return @ctx.at(*override) if override

      @ctx.at(@ctx.backward(@ctx.d(-1)), "16:30")
    end

    def closing_steps(row)
      due = row[:d]
      stamp = due.zero? ? @ctx.at(0, "08:20") : @ctx.at(due, "16:30")
      steps = []
      unless %i[task milestone].include?(row[:ty]) || due.zero?
        steps << { at: @ctx.at(due, "10:30"), who: worker(row), set: { status: :testing, rem: 0 } }
      end
      steps << { at: stamp, who: (row[:ty] == :story ? :ada : :sam), set: { status: :closed, rem: 0 } }
    end

    def talk_steps(row)
      Array(WORK_PACKAGE_TALK[row[:id]]).map do |day, hm, who, text, set|
        { at: @ctx.at(day, hm), who:, note: text, set: set || {} }
      end
    end

    def run(row, steps)
      steps.each do |step|
        User.current = @ctx.user(step[:who])
        wp = step[:create] ? new_work_package(row, step) : WorkPackage.find(row[:id])
        unless step[:create]
          assign(wp, step[:set])
          wp.updated_at = step[:at]
          wp.journal_notes = step[:note] if step[:note]
        end
        wp.save!
      end
    end

    def new_work_package(row, step)
      wp = WorkPackage.new(project:, type_id: TYPES.fetch(row[:ty]), status_id: STATUSES[:new], priority_id: PRIORITIES[:normal],
                           author: @ctx.user(step[:who]), subject: row[:t], description: row[:desc], parent_id: row[:par],
                           schedule_manually: true)
      wp.id = row[:id]
      wp.created_at = wp.updated_at = step[:at]
      wp
    end

    def assign(wp, set)
      set.each do |key, value|
        case key
        when :who then wp.assigned_to_id = PEOPLE.fetch(value)
        when :status then wp.status_id = STATUSES.fetch(value)
        when :prio then wp.priority_id = PRIORITIES.fetch(value)
        when :ver then wp.version_id = value
        when :sprint then wp.sprint_id = sprint_ids.fetch(value)
        when :start then wp.start_date = @ctx.forward(@ctx.d(value))
        when :due then wp.due_date = @ctx.backward(@ctx.d(value))
        when :est then wp.estimated_hours = value
        when :rem then wp.remaining_hours = value
        end
      end
      wp.done_ratio = percent(wp)
    end

    def percent(wp)
      return 100 if wp.status_id == STATUSES[:closed]
      return 0 unless wp.estimated_hours&.positive? && wp.remaining_hours

      (100 * (wp.estimated_hours - wp.remaining_hours) / wp.estimated_hours).round.clamp(0, 100)
    end

    def relations
      RELATIONS.each do |from, to|
        Relation.create!(from_id: from, to_id: to, relation_type: "follows", lag: 0)
      end
    end

    def derive_parents
      by_parent = WorkPackage.where(project:).where.not(parent_id: nil).group_by(&:parent_id)
      by_parent.keys.sort_by { -depth(@rows.fetch(it)) }.each do |parent_id|
        children = by_parent[parent_id]
        parent = WorkPackage.find(parent_id)
        parent.update_columns(derived_values(children, parent))
      end
    end

    def derived_values(children, parent)
      est = children.sum { it.derived_estimated_hours || it.estimated_hours || 0 }
      rem = children.sum { it.derived_remaining_hours || it.remaining_hours || 0 }
      starts = children.filter_map(&:start_date)
      dues = children.filter_map(&:due_date)
      { derived_estimated_hours: est.positive? ? est : nil, derived_remaining_hours: est.positive? ? rem : nil,
        derived_done_ratio: est.positive? ? (100 * (est - rem) / est).round : nil,
        start_date: starts.min || parent.start_date, due_date: dues.max || parent.due_date }
    end

    def reset_sequence
      ActiveRecord::Base.connection.execute("SELECT setval('work_packages_id_seq', (SELECT MAX(id) FROM work_packages))")
    end

    def verify
      WorkPackage.where(project:).find_each do |wp|
        row = @rows.fetch(wp.id)
        wrong = []
        wrong << "status #{wp.status.name}" unless wp.status_id == STATUSES.fetch(row[:st])
        wrong << "assignee #{wp.assigned_to_id}" unless wp.assigned_to_id == PEOPLE[row[:who]]
        wrong << "parent #{wp.parent_id}" unless wp.parent_id == row[:par]
        parent = @rows.values.any? { |other| other[:par] == wp.id }
        wrong << "due #{wp.due_date}" if row[:s] && !parent && wp.due_date != @ctx.backward(@ctx.d(row[:d]))
        @ctx.say("##{wp.id} differs: #{wrong.join(', ')}") if wrong.any?
      end
    end
  end
end
