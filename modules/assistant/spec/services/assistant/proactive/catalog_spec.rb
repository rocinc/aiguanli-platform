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

require "spec_helper"

RSpec.describe Assistant::Proactive::Catalog do
  it "names every moment of the engine spec, the ones raised elsewhere too" do
    expect(described_class.keys).to include(
      "assistant_arrival", "away_digest", "forum_request", "forum_followup", "missed_meeting",
      "request_weigh", "assignee_change_load", "close_with_open_children", "estimate_change_effect"
    )
  end

  it "has no key twice" do
    expect(described_class.keys).to eq(described_class.keys.uniq)
  end

  it "has a title and a sentence for every key in English and Chinese" do
    %i[en zh-CN].each do |locale|
      missing = described_class.keys.reject do
        I18n.exists?("assistant.insights.detectors.#{it}.title", locale) && I18n.exists?("assistant.insights.detectors.#{it}.what", locale)
      end
      expect(missing).to be_empty, "#{locale}: #{missing.join(', ')}"
    end
  end
end
