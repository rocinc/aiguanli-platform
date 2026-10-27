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
    # How well a work package is written down (04 A1 质量画像): whether the
    # description says anything, whether acceptance criteria, an estimate and
    # an assignee are there, how long since anyone touched it, how often its
    # date moved, and how far logged time is from the estimate.
    class WorkPackageQuality
      THIN_DESCRIPTION = 40
      ACCEPTANCE = /acceptance|criteria|验收|完成标准|definition of done|\[ \]|- \[x\]|☐/i

      def initialize(work_package, today: Date.current)
        @work_package = work_package
        @today = today
      end

      attr_reader :work_package

      def description = @description ||= Assistant::Text.plain(work_package.description).to_s.strip

      def thin_description? = description.length < THIN_DESCRIPTION

      def acceptance_criteria? = description.match?(ACCEPTANCE)

      def estimated? = work_package.estimated_hours.present? || work_package.try(:story_points).present?

      def assigned? = work_package.assigned_to_id.present?

      def idle_working_days = Facts.working_days_between(work_package.updated_at.to_date + 1, @today)

      def reschedule_count = History.new(work_package).reschedules.size

      def spent_hours = @spent_hours ||= TimeEntry.where(entity_type: "WorkPackage", entity_id: work_package.id).sum(:hours).to_f.round(1)

      # Logged over estimated, nil without an hour estimate.
      def estimate_ratio
        estimate = work_package.estimated_hours.to_f
        estimate.positive? ? (spent_hours / estimate).round(2) : nil
      end

      def gaps
        [("description" if thin_description?), ("acceptance_criteria" unless acceptance_criteria?),
         ("estimate" unless estimated?), ("assignee" unless assigned?)].compact
      end

      def to_h
        { "gaps" => gaps, "description_length" => description.length, "idle_working_days" => idle_working_days,
          "reschedules" => reschedule_count, "spent_hours" => spent_hours, "estimate_ratio" => estimate_ratio }
      end
    end
  end
end
