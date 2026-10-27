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

module Users::Invitation::PrincipalStep
  class Form < ApplicationForm
    include OpenProject::StaticRouting::UrlHelpers
    include Redmine::I18n

    form do |f|
      f.hidden name: :project_id
      f.hidden name: :principal_type

      f.autocompleter(
        name: :id_or_email,
        label: name_label,
        required: true,
        autocomplete_options: {
          defaultData: true,
          component: "opce-members-autocompleter",
          principalType: model.principal_type.underscore,
          model: selected_principal,
          url: autocomplete_for_member_project_members_path(model.project_id, format: :json, type: model.principal_type),
          focusDirectly: false,
          multiple: false,
          clearable: false,
          appendTo: "##{Users::Invitation::DialogComponent::DIALOG_ID}"
        }
      )

      f.autocompleter(
        name: :role_id,
        required: true,
        include_blank: false,
        label: Role.model_name.human,
        caption: link_translate("users.invite_user_modal.role.description",
                                links: { docs_url: %i[sysadmin_docs roles_and_permissions] }),
        autocomplete_options: {
          multiple: false,
          decorated: true,
          clearable: false,
          focusDirectly: false,
          appendTo: "##{Users::Invitation::DialogComponent::DIALOG_ID}"
        }
      ) do |role_list|
        ProjectRole
          .givable
          .ordered_by_builtin_and_position
          .find_each do |role|
          role_list.option(label: role.name, value: role.id)
        end
      end

      if model.principal_type != "PlaceholderUser"
        f.text_area(
          name: :message,
          label: I18n.t("users.invite_user_modal.message.label"),
          caption: I18n.t("users.invite_user_modal.message.description"),
          rows: 5,
          style: "resize: none"
        )
      end
    end

    def selected_principal # rubocop:disable Metrics/AbcSize
      return if model.id_or_email.blank?

      if EmailValidator.valid?(model.id_or_email)
        { name: I18n.t("members.invite_by_mail", mail: model.id_or_email), id: model.id_or_email }
      else
        principal = Principal.visible.find_by(id: model.id_or_email)
        { name: principal&.name || "User #{id_or_email}", id: principal.id }
      end
    end

    def name_label
      if model.principal_type == "User"
        I18n.t("activerecord.attributes.users/invitation/form_model.id_or_email")
      else
        User.human_attribute_name(:name)
      end
    end
  end
end
