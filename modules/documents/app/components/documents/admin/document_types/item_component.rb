# frozen_string_literal: true

# -- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2010-2024 the OpenProject GmbH
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

module Documents
  module Admin
    module DocumentTypes
      class ItemComponent < ::Admin::Enumerations::ItemComponent
        alias_method :document_type, :enumeration

        def deletion_enumeration(menu)
          menu.with_item(
            label: I18n.t(:button_delete),
            scheme: :danger,
            tag: :a,
            content_arguments: {
              data: { controller: "async-dialog" }
            },
            href: delete_dialog_admin_settings_document_type_path(document_type)
          ) do |item|
            item.with_leading_visual_icon(icon: :trash)
          end
        end

        def colored?
          false
        end
      end
    end
  end
end
