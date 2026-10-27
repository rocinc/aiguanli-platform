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
  # Fills the turbo frame the work package page reserves under its title. An
  # empty frame is answered when there is nothing to say, so the page keeps
  # no gap.
  class ObjectLinesController < ApplicationController
    before_action :find_work_package
    authorization_checked! :show

    FRAME_ID = "assistant-wp-line-frame"

    def show
      marks = Assistant::MarksComponent.new(object: @work_package, user: current_user, parts: %i[decisions])
      line = Assistant::ObjectLineComponent.new(object: @work_package, user: current_user)

      render html: helpers.turbo_frame_tag(FRAME_ID) { helpers.safe_join([render_to_string(marks, layout: false),
                                                                           render_to_string(line, layout: false)]) }
    end

    private

    def find_work_package
      @work_package = WorkPackage.visible(current_user).find_by(id: params[:work_package_id])
      head(:no_content) unless @work_package
    end
  end
end
