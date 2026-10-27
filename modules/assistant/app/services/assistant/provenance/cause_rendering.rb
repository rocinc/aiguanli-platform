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
  module Provenance
    # Renders "Changed by AI assistant on behalf of Sam, based on Sprint 6
    # planning item 3" in the activity, linking back to the basis.
    module CauseRendering
      def render(key, values, options = { html: true })
        cause = values.last
        return super unless cause.is_a?(Hash) && cause["type"] == "assistant_action"

        @cause = cause
        @html = options[:html]
        assistant_action_message
      end

      private

      def assistant_action_message
        actor = assistant_actor_text
        basis = cause["basis"].presence
        undo = assistant_action_link

        return [actor, basis && assistant_basis_text(basis)].compact.join(" ") unless html?

        parts = [content_tag(:strong, actor)]
        parts << " " << assistant_basis_html(basis) if basis
        parts << " " << undo if undo
        safe_join(parts)
      end

      def assistant_actor_text
        signed = User.find_by(id: cause["signed_by_id"])
        return I18n.t("assistant.provenance.drafted", assistant: AssistantUser.instance.name, user: signed.name) if signed

        user = User.find_by(id: cause["on_behalf_of_id"])
        if user
          I18n.t("assistant.provenance.on_behalf", assistant: AssistantUser.instance.name, user: user.name)
        else
          I18n.t("assistant.provenance.by", assistant: AssistantUser.instance.name)
        end
      end

      def assistant_basis_text(basis)
        I18n.t("assistant.provenance.basis", basis: basis["label"].presence || basis["quote"])
      end

      def assistant_basis_html(basis)
        text = assistant_basis_text(basis)
        target = Assistant::Provenance.url_for_basis(basis)
        label = target ? link_to(text, target, class: "assistant-provenance--basis") : text
        return label if basis["quote"].blank?

        safe_join([label, " ", content_tag(:q, basis["quote"].truncate(80), class: "assistant-provenance--quote")])
      end

      def assistant_action_link
        return unless cause["action_id"]

        link_to(I18n.t("assistant.provenance.details"), assistant_action_path(cause["action_id"]),
                class: "assistant-provenance--details", data: { turbo_frame: "_top" })
      end
    end
  end
end
