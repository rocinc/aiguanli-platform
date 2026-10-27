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
  module Facts
    # How long a kind of work usually takes in this project, read off the
    # hours people logged on similar finished work packages. The kind is the
    # time-entry activity ("测试" for an acceptance check, "开发" for building);
    # similarity is on the subject's words.
    class Estimate
      ACTIVITY_WORDS = {
        "test" => %w[验收 测试 测一下 回归 test qa verify review 评审 看一下 看看],
        "spec" => %w[需求 方案 设计 调研 spec design],
        "dev" => %w[开发 实现 修复 fix build implement 联调]
      }.freeze
      ACTIVITY_NAMES = {
        "test" => %w[测试 test testing qa],
        "spec" => %w[需求 specification design],
        "dev" => %w[开发 development]
      }.freeze
      MIN_SAMPLES = 2

      def initialize(project, text:, activity: nil, subject: nil)
        @project = project
        @text = text.to_s
        @kind = activity.presence || self.class.kind_of(@text)
        @subject = subject
      end

      attr_reader :kind

      def self.kind_of(text)
        down = text.to_s.downcase
        ACTIVITY_WORDS.find { |_, words| words.any? { down.include?(it) } }&.first || "dev"
      end

      def samples
        @samples ||= begin
          hours = scope.group(:entity_id).sum(:hours)
          subjects = WorkPackage.where(id: hours.keys).pluck(:id, :subject).to_h
          hours.map do |id, h|
            { "id" => id, "subject" => subjects[id], "hours" => h.to_f.round(1), "similarity" => similarity(subjects[id]) }
          end
               .sort_by { -it["similarity"] }
        end
      end

      def similar = samples.select { it["similarity"] >= 0.2 }

      def basis = similar.size >= MIN_SAMPLES ? similar : samples

      def hours
        values = basis.map { it["hours"] }.sort
        return nil if values.empty?

        mid = values.size / 2
        (values.size.odd? ? values[mid] : (values[mid - 1] + values[mid]) / 2.0).round(1)
      end

      def sufficient? = basis.size >= MIN_SAMPLES

      def because
        return I18n.t("assistant.facts.estimate.none", activity: activity_label) if hours.nil?

        I18n.t("assistant.facts.estimate.because", hours:, count: basis.size, activity: activity_label,
                                                   examples: basis.first(3).map { "##{it['id']}" }.join(", "))
      end

      def to_h
        { "hours" => hours, "activity" => activity_label, "samples" => basis.first(5), "sufficient" => sufficient?,
          "because" => because }
      end

      def activity_ids
        names = ACTIVITY_NAMES.fetch(kind, [])
        TimeEntryActivity.all.select { |a| names.any? { a.name.downcase.include?(it) } }.map(&:id)
      end

      private

      def activity_label
        TimeEntryActivity.where(id: activity_ids).pick(:name) || kind
      end

      def scope
        relation = TimeEntry.where(project: @project, entity_type: "WorkPackage")
        relation = relation.where(activity_id: activity_ids) if activity_ids.any?
        relation = relation.where.not(entity_id: @subject.id) if @subject
        relation
      end

      def similarity(subject)
        reference = [@subject&.subject, @text].compact.join(" ")
        share, = Assistant::Text.overlap(reference, subject.to_s)
        share.round(2)
      end
    end
  end
end
