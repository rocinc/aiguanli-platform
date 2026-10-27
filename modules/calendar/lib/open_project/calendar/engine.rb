# OpenProject Calendar module
#
# Copyright (C) the OpenProject GmbH
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

module OpenProject::Calendar
  class Engine < ::Rails::Engine
    engine_name :openproject_calendar

    include OpenProject::Plugins::ActsAsOpEngine

    register "openproject-calendar",
             author_url: "https://www.openproject.org",
             bundled: true,
             settings: {} do
      plugin = self
      Rails.application.reloader.to_prepare do
        plugin.permission :share_calendars,
                          {},
                          permissible_on: :project,
                          dependencies: %i[view_work_packages],
                          contract_actions: { calendar: %i[read] }
      end
    end

    add_view :WorkPackagesCalendar,
             contract_strategy: "Calendar::Views::ContractStrategy"

    initializer "calendar.register_mimetypes" do
      # next if defined? Mime::XLS

      Mime::Type.register("text/calendar", :ics)
    end

    initializer "calendar.configuration" do
      ::Settings::Definition.add "ical_enabled",
                                 default: true,
                                 format: :boolean
    end
  end
end
