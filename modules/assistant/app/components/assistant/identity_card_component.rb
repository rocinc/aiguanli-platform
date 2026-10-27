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
  # What the hover card says when the person hovered is the assistant: who it
  # is, who may call it, and what it looks after in the projects of the viewer.
  class IdentityCardComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    MAX_PROJECTS = 3

    def initialize(user:, viewer: User.current)
      super()
      @user = user
      @viewer = viewer
    end

    attr_reader :user, :viewer

    def projects
      @projects ||= Project.allowed_to(viewer, :use_assistant)
                           .where(id: Member.where(user_id: user.id).select(:project_id))
                           .order(:name).to_a
    end

    def duty_count(project) = Assistant::Duty.active.where(project:).count

    def project_lines
      projects.first(MAX_PROJECTS).map do |project|
        count = duty_count(project)
        key = count.zero? ? "no_duties" : "duties"
        t("assistant.identity_card.#{key}", project: project.name, count:)
      end
    end

    def call
      flex_layout(classes: "op-user-hover-card", data: { test_selector: "assistant-identity-card" }) do |flex|
        flex.with_row do
          render(Users::AvatarComponent.new(user:, show_name: false, link: false, hover_card: { active: false }))
        end
        flex.with_row do
          render(Primer::Beta::Text.new(font_weight: :semibold)) { user.name }
        end
        flex.with_row do
          render(Primer::Beta::Text.new(font_size: :small, color: :muted)) { t("assistant.identity_card.who") }
        end
        flex.with_row do
          render(Primer::Beta::Text.new(font_size: :small)) do
            projects.any? ? t("assistant.identity_card.call") : t("assistant.identity_card.cannot_call")
          end
        end
        project_lines.each do |line|
          flex.with_row { render(Primer::Beta::Text.new(font_size: :small, color: :muted)) { line } }
        end
      end
    end
  end
end
