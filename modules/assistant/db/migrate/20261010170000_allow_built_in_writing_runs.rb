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

# The editor's built-in writing (continue, write) runs without a configured
# text transform action.
class AllowBuiltInWritingRuns < ActiveRecord::Migration[8.0]
  def change
    change_column_null :ai_text_transform_runs, :ai_text_transform_action_id, true
  end
end
