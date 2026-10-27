# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  # The page object a panel request is about, given as a GlobalID. Only what
  # the person may see is found; anything else is as if nothing was given.
  module ContextLookup
    CONTEXT_TYPES = (%w[WorkPackage Project Meeting] + Assistant::Conversations::Context.type_names).freeze

    private

    def locate_context(gid)
      return if gid.blank?

      record = GlobalID::Locator.locate(gid, only: CONTEXT_TYPES.map(&:constantize))
      record if record && visible?(record)
    rescue ActiveRecord::RecordNotFound, URI::InvalidURIError, NameError
      nil
    end

    def visible?(record)
      case record
      when WorkPackage then record.visible?(current_user)
      when Project then record.visible?(current_user)
      when Meeting then record.visible?(current_user)
      else Assistant::Conversations::Context.for(record)&.visible_to?(current_user)
      end
    end

    def atom_gid?(gid)
      Assistant::Conversations::Context.type_names.any? { gid.to_s.include?("/#{it}/") }
    end

    def project_of(record) = record.is_a?(Project) ? record : record.try(:project)

    def allowed_in?(project)
      return current_user.admin? || current_user.allowed_in_any_project?(:use_assistant) if project.nil?

      Assistant::Surface.available?(project, current_user)
    end
  end
end
