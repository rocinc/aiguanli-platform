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
  module Reasoning
    module Tools
      class EstimateTool < Base
        define "estimate",
               "How many hours a kind of work usually takes here, from hours logged on similar finished work.",
               { text: { type: "string", description: "What the work is, e.g. \"验收全文检索\"" },
                 ref: { type: "string", description: "Work package the work is about, if any" },
                 activity: { type: "string", enum: %w[test spec dev] } },
               required: %w[text]

        def call(args)
          wp = args["ref"].present? ? context.work_package(args["ref"]) : nil
          Assistant::Facts::Estimate.new(project, text: args["text"], activity: args["activity"], subject: wp).to_h
        end
      end
    end
  end
end
