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
  # "Today" heads a new my page, across its width, for whoever may use the
  # assistant (03 §3.5 渠道 3); the platform's widgets move one row down. Pages
  # people already arranged stay as they are.
  module MyPageDefaults
    module_function

    def apply!
      registration = ::MyPage::GridRegistration
      return if registration.instance_variable_get(:@assistant_today)

      host = registration._defaults
      registration._defaults = -> { with_today(host.call) }
      registration.instance_variable_set(:@assistant_today, true)
    end

    def with_today(params)
      return params unless ::Assistant::PanelDialogComponent.anywhere?(User.current)

      columns = params[:column_count]
      widgets = params[:widgets].map { it.merge(start_row: it[:start_row] + 1, end_row: it[:end_row] + 1) }
      today = { identifier: "assistant_today", start_row: 1, end_row: 2, start_column: 1, end_column: columns + 1,
                options: { name: I18n.t("js.grid.widgets.assistant_today.title") } }
      params.merge(row_count: params[:row_count] + 1, widgets: [today, *widgets])
    end
  end
end
