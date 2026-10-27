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
  # A project's own say over the assistant, as the project settings page
  # shows and writes it.
  class ProjectPage
    def initialize(project)
      @project = project
    end

    attr_reader :project

    def preference = @preference ||= Assistant::Preference.for(project)

    def settings = @settings ||= Assistant::Proactive::ProjectSettings.for(project)

    def roles
      @roles ||= ProjectRole.givable.joins(:role_permissions).where(role_permissions: { permission: "use_assistant" })
                            .where.not(name: Assistant::Membership::ROLE_NAME).reorder(:position).to_a
    end

    def role_level(role) = preference.role_levels[role.id.to_s]

    def rules = Assistant::Proactive::Catalog.keys

    delegate :enabled?, to: :settings

    def members
      @members ||= User.active.where.not(type: "AssistantUser").where(id: project.members.select(:user_id))
                       .reorder(:lastname, :firstname).to_a
    end

    def leads = settings.lead_ids

    def duty_kinds = Assistant::Duty::KINDS

    delegate :duty_allowed?, to: :settings

    def in_use?(kind) = duties_in_use.include?(kind)

    delegate :token_cap, to: :settings

    def tokens_used = Assistant::Usage.this_month.where(project:).tokens

    def update!(attributes)
      Assistant::Proactive::ProjectSettings.write!(project, **write_arguments(attributes))
      pause_duties_no_longer_allowed
    end

    private

    def write_arguments(attributes)
      { level: attributes[:level], role_levels: attributes[:role_levels].to_h.slice(*roles.map { it.id.to_s }),
        enabled: Array(attributes[:rules]), lead_ids: Array(attributes[:lead_ids]) & members.map { it.id.to_s },
        duties: Array(attributes[:duties]), token_cap: attributes[:token_cap].to_i }
    end

    def duties_in_use = @duties_in_use ||= Assistant::Duty.where(project:, active: true).pluck(:kind)

    def pause_duties_no_longer_allowed
      settings = Assistant::Proactive::ProjectSettings.for(project)
      Assistant::Duty.where(project:, active: true).find_each { |duty| duty.update!(active: false) unless settings.duty_allowed?(duty.kind) }
    end
  end
end
