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
  # The side note under a work package's header right after someone saved a
  # decision, or while they are writing a new work package's title. Answers
  # an empty frame when there is nothing to say, so the page keeps no gap.
  class AsidesController < ApplicationController
    before_action :find_work_package, only: %i[show field]
    authorization_checked! :show, :field, :duplicate

    FRAME_ID = "assistant-wp-aside-frame"

    # The rows of the attribute list that carry a side note, by the name the page gives the row, and the
    # fields a note may name for it. The dates row stands for start date, due date and the milestone date.
    FIELD_SLOTS = {
      "date" => %w[date startDate dueDate],
      "assignee" => %w[assignee],
      "status" => %w[status],
      "version" => %w[version],
      "estimatedTime" => %w[estimatedTime],
      "remainingTime" => %w[remainingTime]
    }.freeze
    PROMISE_SLOT = "date"

    def show
      signal = Assistant::Proactive::Immediate.fresh_for(@work_package, current_user, except: placed_fields)
      frame((signal if signal && Assistant::Surface.available?(@work_package.project, current_user)))
    end

    def field
      slot = params[:field].to_s
      return head(:no_content) unless FIELD_SLOTS.key?(slot) && Assistant::Surface.available?(@work_package.project, current_user)

      signal = Assistant::Proactive::Immediate.fresh_for(@work_package, current_user, only: FIELD_SLOTS.fetch(slot))
      render html: helpers.turbo_frame_tag("assistant-wp-field-aside-#{slot}") { field_html(slot, signal) }
    end

    def duplicate
      project = Project.visible(current_user).find_by(id: params[:project_id])
      signal = project && Assistant::DuplicateAside.for(project:, user: current_user, subject: params[:subject],
                                                        type_id: params[:type_id])
      frame(signal)
    end

    private

    def frame(signal)
      inner = signal ? aside_html(signal) : ""
      render html: helpers.turbo_frame_tag(FRAME_ID) { inner }
    end

    def placed_fields
      params[:placed].to_s.split(",").filter_map { FIELD_SLOTS[it] }.flatten
    end

    def field_html(slot, signal)
      parts = []
      if slot == PROMISE_SLOT
        parts << render_to_string(Assistant::MarksComponent.new(object: @work_package, user: current_user, parts: %i[promises]),
                                  layout: false)
      end
      parts << aside_html(signal) if signal
      helpers.safe_join(parts)
    end

    def aside_html(signal)
      notice = Assistant::NoticeComponent.new(signal:, user: current_user, density: :line, heading_level: 2)
      helpers.content_tag(:div, render_to_string(notice, layout: false), class: "assistant-wp-aside")
    end

    def find_work_package
      @work_package = WorkPackage.visible(current_user).find_by(id: params[:work_package_id])
      head(:no_content) unless @work_package
    end
  end
end
