# -- copyright
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
# ++
module CostReports
  class Menu < Submenu
    attr_reader :view_type, :project

    def initialize(project: nil, params: nil)
      @project = project
      @params = params

      super(view_type:, project:, params:)
    end

    PRESET_FILTER = 'spent_on >=d "%<days>d"'
    PRESETS = {
      default_report: {},
      time_entries: { filters: format(PRESET_FILTER, days: 30), rows: "user_id,work_package_id", columns: "week", unit: -1 },
      by_version: { filters: format(PRESET_FILTER, days: 90), rows: "version_id,work_package_id", columns: "tmonth", unit: -1 }
    }.freeze
    PRESET_ICONS = { default_report: "graph", time_entries: "clock", by_version: "milestone" }.freeze

    def menu_items
      [
        OpenProject::Menu::MenuGroup.new(header: nil, children: preset_items),
        OpenProject::Menu::MenuGroup.new(header: I18n.t("label_public_report_plural"), children: global_queries),
        OpenProject::Menu::MenuGroup.new(header: I18n.t("label_private_report_plural"), children: custom_queries)
      ]
    end

    def preset_items
      PRESETS.map do |key, preset|
        menu_item(title: I18n.t("cost_reports_menu.#{key}"),
                  icon_key: PRESET_ICONS.fetch(key),
                  query_params: preset,
                  selected: preset_selected?(preset),
                  href: preset_path(preset))
      end
    end

    def global_queries
      CostReport.public_in(project)
        .pluck(:id, :name)
        .map { |id, name| menu_item(title: name, query_params: query_params(id)) }
        .sort_by { |item| item.title.downcase }
    end

    def custom_queries
      CostReport.private_in(project, User.current)
        .pluck(:id, :name)
        .map { |id, name| menu_item(title: name, query_params: query_params(id)) }
        .sort_by { |item| item.title.downcase }
    end

    def selected?(query_params)
      query_params[:id].to_s == params[:id]
    end

    def preset_selected?(preset)
      return false if params[:id].present?

      CostReports::ParamsToReport::CONFIGURATION_PARAMS.all? do |key|
        params[key].to_s == preset[key].to_s
      end
    end

    def preset_path(preset)
      if project.present?
        project_reporting_cost_reports_path(project, preset)
      else
        global_reporting_cost_reports_path(preset)
      end
    end

    def query_params(id)
      { id: }
    end

    def query_path(query_params)
      if project.present?
        project_reporting_cost_report_path(project, query_params[:id])
      else
        reporting_cost_report_path(query_params[:id])
      end
    end
  end
end
