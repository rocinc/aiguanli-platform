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
    # Work in other projects that is about the same thing as a topic here,
    # as far as the viewer may see it: what was done, by whom, and how
    # closely it matches. Finished work comes first; it is the reusable kind.
    class Elsewhere
      WINDOW = 365.days
      MIN_MATCH = 0.5
      PREFILTER = 8

      Match = Data.define(:work_package, :share, :doer, :closed)

      def initialize(project, topic, viewer:, today: Date.current)
        @project = project
        @topic = topic.to_s
        @viewer = viewer
        @today = today
      end

      def matches(limit: 3)
        return [] if terms.empty?

        candidates.filter_map do |wp|
          share = Assistant::Text.overlap("#{wp.subject} #{Assistant::Text.plain(wp.description).first(300)}", @topic).first
          share = [share, Assistant::Text.overlap(@topic, wp.subject).first].max
          next if share < MIN_MATCH

          Match.new(work_package: wp, share: share.round(2), doer: doer_of(wp), closed: !Facts.open?(wp))
        end.sort_by { [it.closed ? 0 : 1, -it.share] }.first(limit)
      end

      private

      def terms = @terms ||= Assistant::Text.terms(@topic).to_a.max_by(PREFILTER, &:length)

      # Cheap in SQL, exact in Ruby: any term in the subject is enough to be looked at.
      def candidates
        like = terms.map { "%#{ActiveRecord::Base.sanitize_sql_like(it)}%" }
        WorkPackage.visible(@viewer).where.not(project_id: @project.id)
                   .where(updated_at: (@today - WINDOW).beginning_of_day..)
                   .where(Array.new(like.size, "work_packages.subject ILIKE ?").join(" OR "), *like)
                   .includes(:project, :assigned_to, :status).limit(200).to_a
      end

      def doer_of(wp)
        person = wp.assigned_to || wp.responsible
        person if person.is_a?(User) && person.active? && !person.is_a?(AssistantUser)
      end
    end
  end
end
