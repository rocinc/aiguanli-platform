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
  # One person's say over the assistant: how forward it is, how often it may
  # interrupt, the brief, the rules they turned off and what they let it do
  # without asking.
  class MySettings
    MuteRow = Data.define(:key, :project)
    CAP_CHOICES = (1..6).to_a.freeze

    def self.rule_title(key)
      I18n.t("assistant.insights.detectors.#{key}.title", default: I18n.t("assistant.settings.unknown_rule"))
    end

    def initialize(user)
      @user = user
    end

    attr_reader :user

    def preference = @preference ||= Assistant::Preference.for(user)

    def projects
      @projects ||= Project.active.allowed_to(user, :use_assistant).reorder(:name).to_a
    end

    delegate :project_level, to: :preference

    def chosen_cap = (preference.interrupt_cap if preference.cap_chosen?)

    def brief_clock = Assistant::Proactive::Timing.new(user).brief_clock

    def mutes
      @mutes ||= preference.muted_detectors.map { MuteRow.new(it, nil) } +
                 projects.flat_map { |project| preference.muted_in(project).map { MuteRow.new(it, project) } }
    end

    def grants
      @grants ||= Assistant::Grant.live.where(granted_by: user).includes(:project).order(:created_at)
                                  .select { it.project.active? && user.allowed_in_project?(:manage_assistant, it.project) }
    end

    def update!(attributes)
      preference.assign_attributes(proactivity: attributes[:proactivity].presence_in(Assistant::Preference::LEVELS),
                                   brief_email: ActiveModel::Type::Boolean.new.cast(attributes[:brief_email]))
      preference.choose_cap(attributes[:interrupt_cap].to_i.presence_in(CAP_CHOICES))
      preference.project_levels = preference.project_levels.merge(chosen_project_levels(attributes[:project_levels]))
      preference.save!
    end

    def unmute!(key, project_id)
      project = projects.find { it.id.to_s == project_id.to_s }
      if project
        preference.unmute_in!(key, project)
      else
        preference.unmute!(key)
      end
    end

    def revoke!(id)
      grant = grants.find { it.id == id.to_i } or raise ActiveRecord::RecordNotFound
      grant.revoke!
      grant
    end

    private

    def chosen_project_levels(levels)
      levels.to_h.slice(*projects.map { it.id.to_s }).transform_values { it.presence_in(Assistant::Preference::LEVELS) }
    end
  end
end
