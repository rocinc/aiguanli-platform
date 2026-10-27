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
class RemoveBimLeftovers < ActiveRecord::Migration[8.1]
  BIM_PERMISSIONS = %w[
    view_ifc_models
    manage_ifc_models
    view_linked_issues
    manage_bcf
    delete_bcf
    save_bcf_queries
    manage_public_bcf_queries
  ].freeze

  BIM_TABLES = %i[bcf_comments bcf_viewpoints bcf_issues ifc_models].freeze

  def up
    execute "DELETE FROM enabled_modules WHERE name = 'bim'"
    execute <<~SQL.squish
      DELETE FROM role_permissions WHERE permission IN (#{BIM_PERMISSIONS.map { |name| connection.quote(name) }.join(', ')})
    SQL

    BIM_TABLES.each { |table| drop_table table, if_exists: true, force: :cascade }
  end

  def down; end
end
