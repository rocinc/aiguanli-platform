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

require "spec_helper"

RSpec.describe Assistant::Text do
  describe ".day" do
    it "writes the day with its weekday" do
      travel_to(Date.new(2026, 9, 1)) do
        expect(described_class.day(Date.new(2026, 9, 30))).to eq("9/30 (Wed)")
        I18n.with_locale(:"zh-CN") { expect(described_class.day(Date.new(2026, 9, 30))).to eq("9/30（周三）") }
      end
    end

    it "adds the year only when it is not this one" do
      travel_to(Date.new(2026, 9, 1)) do
        expect(described_class.day(Date.new(2027, 1, 5))).to eq("2027/1/5 (Tue)")
      end
    end
  end
end
