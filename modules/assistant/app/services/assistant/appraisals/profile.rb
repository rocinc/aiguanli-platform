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
  module Appraisals
    # Eight dimensions for one member, each with its value, the team median,
    # how it was computed, the evidence behind it, the member's own notes, and
    # whether there is enough to conclude anything.
    class Profile
      DIMENSIONS = %w[delivery estimation output quality collaboration word knowledge load].freeze
      MIN_SAMPLES = 3

      def initialize(facts, team: nil, viewer: nil)
        @facts = facts
        @team = team
        @viewer = viewer
      end

      attr_reader :facts

      delegate :user, :project, :from, :to, to: :facts

      def values = @values ||= DIMENSIONS.index_with { send(:"compute_#{_1}") }

      def value(dimension) = values.dig(dimension, "value")

      def to_h
        notes = Assistant::AppraisalNote.where(subject: user, project:).order(:created_at).group_by(&:metric_key)
        {
          "user" => { "id" => user.id, "name" => user.name },
          "period" => { "from" => from.iso8601, "to" => to.iso8601 },
          "dimensions" => values.to_h do |key, dim|
            [key, dim.merge("team_median" => @team&.median(key), "previous" => previous&.value(key),
                            "notes" => Array(notes[key]).map { { "note" => _1.note, "on" => _1.created_at.to_date.iso8601 } })]
          end,
          "situation" => situation,
          "general_notes" => Array(notes["general"]).map { { "note" => _1.note, "on" => _1.created_at.to_date.iso8601 } }
        }
      end

      # The same person over the period just before, for the trend.
      def previous
        return @previous if defined?(@previous)

        length = (to - from).to_i
        @previous = Profile.new(MemberFacts.new(user:, project:, from: from - length - 1, to: from - 1))
      end

      def record_view!
        return if @viewer.nil? || @viewer == user

        Assistant::AppraisalView.create!(viewer: @viewer, subject: user, project:, created_at: Time.current)
      end

      private

      def dim(value, because, evidence: [], sample: nil, unit: nil, extra: {})
        insufficient = sample && sample < MIN_SAMPLES
        { "value" => insufficient ? nil : value, "raw" => value, "unit" => unit, "because" => because,
          "evidence" => evidence.first(8), "sample" => sample, "insufficient" => insufficient || false }.merge(extra)
      end

      def t(key, **) = I18n.t("assistant.appraisals.because.#{key}", **)

      def points?(project)
        RequestStore.fetch(:"assistant_points_#{project.id}") do
          WorkPackage.where(project:, status_id: Assistant::Facts.closed_status_ids).where("story_points > 0").exists?
        end
      end

      def ref(wp) = "##{wp.id} #{wp.subject}"

      def compute_delivery
        dated = facts.deliveries.select(&:due)
        on_time = dated.count { _1.late_days.zero? }
        raw_on_time = dated.count { Assistant::Facts.working_days_between(_1.due + 1, _1.closed_on).zero? }
        rate = dated.any? ? (on_time * 100.0 / dated.size).round : nil
        raw = dated.any? ? (raw_on_time * 100.0 / dated.size).round : nil
        late = dated.reject { _1.late_days.zero? }
        because = [t("delivery", on_time:, count: dated.size, raw: raw || "–", blocked: dated.sum(&:blocked_days),
                                 renegotiated: dated.count(&:renegotiated)),
                   (t("carried_over", count: facts.carried_over) if facts.carried_over.positive?)].compact
        dim(rate, because.join(t("separator")),
            evidence: late.map { "#{ref(_1.work_package)}: +#{_1.late_days}d" } +
                      dated.select { _1.blocked_days.positive? }.map { "#{ref(_1.work_package)}: #{t('blocked_days', days: _1.blocked_days)}" },
            sample: dated.size, unit: "%", extra: { "uncorrected" => raw, "carried_over" => facts.carried_over })
      end

      def compute_estimation
        ratios = facts.estimate_ratios.sort
        median = ratios.empty? ? nil : ratios[ratios.size / 2]
        spread = ratios.size > 1 ? (ratios.last - ratios.first).round(2) : nil
        dim(median, ratios.empty? ? t("estimation_none") : t("estimation", median:, count: ratios.size, spread: spread || "–"),
            sample: ratios.size, unit: "×", extra: { "spread" => spread })
      end

      def compute_output
        done = facts.deliveries
        points = done.sum { _1.work_package.story_points.to_i }
        capacity = facts.capacity.hours
        # Weighted by complexity where the team sizes its work in points (05 §3 按难度比较).
        size = points?(project) ? points : done.size
        per_week = capacity.positive? ? (size / (capacity / 40.0)).round(1) : nil
        dim(per_week, t("output", count: done.size, points:, capacity:, absent: facts.absent_days,
                                  firefight: done.count(&:firefight)),
            evidence: done.first(8).map { ref(_1.work_package) }, sample: done.size, unit: "/40h",
            extra: { "done" => done.size, "points" => points, "counted_in" => points?(project) ? "points" : "work_packages", "firefight" => done.select(&:firefight).map { ref(_1.work_package) },
                     "by_type" => done.group_by { _1.work_package.type&.name }.transform_values(&:size) })
      end

      def compute_quality
        done = facts.deliveries.size
        rate = done.positive? ? (facts.reopened * 100.0 / done).round : nil
        passed, finished = facts.check_runs
        defects = facts.related_defects
        dim(rate, [t("quality", reopened: facts.reopened, count: done),
                   (t("quality_defects", count: defects.size) if defects.any?),
                   (t("quality_checks", passed:, count: finished) if finished.positive?)].compact.join(t("separator")),
            evidence: defects.map { ref(it) }, sample: done, unit: "%",
            extra: { "defects" => defects.size, "checks_passed" => passed, "checks" => finished })
      end

      def compute_collaboration
        answered = facts.answered_for_others
        comments = facts.comments_on_others
        meetings = facts.meeting_items_taken
        depended = facts.depended_on_by
        score = answered * 3 + comments + meetings * 2 + depended
        days = facts.response_days.sort
        response = days.empty? ? nil : days[days.size / 2]
        dim(score, [t("collaboration", answered:, comments:, meetings:, depended:),
                    (t("response", days: response, count: days.size) if response)].compact.join(t("separator")),
            sample: nil,
            extra: { "answered" => answered, "comments_on_others" => comments, "meeting_items" => meetings,
                     "depended_on_by" => depended, "response_working_days" => response })
      end

      def compute_word
        tally = facts.word_outcomes
        settled = tally.except("open").values.sum
        kept = tally["kept"] + tally["renegotiated"]
        rate = settled.positive? ? (kept * 100.0 / settled).round : nil
        dim(rate, t("word", kept: tally["kept"], renegotiated: tally["renegotiated"], late: tally["late"],
                            silent: tally["silent"], withdrawn: tally["withdrawn"], open: tally["open"]),
            evidence: facts.commitments.first(8).map { "“#{_1.quote.truncate(40)}”" }, sample: settled, unit: "%",
            extra: { "tally" => tally })
      end

      def compute_knowledge
        edits = facts.wiki_edits
        newcomers = facts.helped_newcomers
        dim(edits + facts.answered_for_others + newcomers,
            [t("knowledge", edits:, answered: facts.answered_for_others),
             (t("newcomers", count: newcomers) if newcomers.positive?)].compact.join(t("separator")),
            extra: { "helped_newcomers" => newcomers })
      end

      def compute_load
        capacity = facts.capacity.hours
        logged = facts.hours_logged
        utilisation = capacity.positive? ? (logged * 100.0 / capacity).round : nil
        dim(utilisation, [t("load", logged:, capacity:, absent: facts.absent_days,
                                    blocked: facts.deliveries.sum(&:blocked_days)),
                          (t("switches", days: facts.switch_days) if facts.switch_days.positive?)].compact.join(t("separator")),
            unit: "%", extra: { "capacity" => capacity, "logged" => logged, "switch_days" => facts.switch_days })
      end

      def situation
        {
          "absent_days" => facts.absent_days,
          "blocked_working_days" => facts.deliveries.sum(&:blocked_days),
          "firefighting" => facts.deliveries.select(&:firefight).map { ref(_1.work_package) },
          "renegotiated_early" => facts.deliveries.count(&:renegotiated) + facts.word_outcomes["renegotiated"],
          "switch_days" => facts.switch_days
        }
      end
    end
  end
end
