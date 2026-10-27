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
  # The ✦ after a work package in lists (S3.3): the sentence the person would
  # read on top of the page, known for every row from one query per request.
  module ListMarks
    module_function

    def headline(work_package, user)
      return unless user&.logged?

      sentence = headlines(user)[work_package.id]
      sentence if sentence && Surface.available?(work_package.project, user)
    end

    def headlines(user)
      RequestStore.fetch([:assistant_list_marks, user.id]) do
        ObjectLineComponent.live_for(user).where(subject_type: "WorkPackage")
                           .pluck(:subject_id, Arel.sql("payload ->> 'headline'"))
                           .each_with_object({}) { |(id, headline), marks| marks[id] ||= headline.to_s }
      end
    end
  end
end
