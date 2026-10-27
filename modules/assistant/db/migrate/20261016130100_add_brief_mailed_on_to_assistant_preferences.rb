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

class AddBriefMailedOnToAssistantPreferences < ActiveRecord::Migration[8.0]
  def change
    add_column :assistant_preferences, :brief_mailed_on, :date
  end
end
