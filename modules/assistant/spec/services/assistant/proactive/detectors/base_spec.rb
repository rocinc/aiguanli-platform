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
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

# The one sentence of a notice is at most 40 characters (03 L1.2, L6). The detectors shorten what a person wrote into it
# (Detectors::Base#t), down to MIN_KEPT characters; so the copy is checked with that much user text and the longest
# value every other placeholder is expected to take.

# The one sentence of a notice is at most 40 characters (03 L1.2, L6). The detectors shorten what a person wrote into it
# (Detectors::Base#t), down to MIN_KEPT characters; so the copy is checked with that much user text and the longest
# value every other placeholder is expected to take.
RSpec.describe Assistant::Proactive::Detectors::Base do
  let(:limit) { 40 }
  let(:longest) do
    {
      "ref" => "#1234", "name" => "Frank", "taker" => "Frank", "date" => "10/21（周三）", "finish" => "10/21（周三）",
      "target" => "10/21（周三）", "hours" => "44", "over" => "44", "short" => "48", "free" => "-12", "count" => "12",
      "times" => "3", "slip" => "5", "days" => "15", "done" => "90", "open" => "12", "percent" => "90", "estimate" => "40",
      "spent" => "120", "budget" => "100", "factor" => "2.5", "requests" => "5", "number" => "1234",
      "from" => "10/21（周三）", "to" => "10/28（周三）", "load" => "120", "capacity" => "100", "mismatched" => "3",
      "conflicts" => "3", "one" => "#1234", "other" => "#1234", "before" => "480", "after" => "-20", "list" => "#1234、#1235",
      "what" => "#1234 等 12 项", "version" => "v2.0 团队版", "sprint" => "Sprint 1234", "status" => "进行中",
      "type" => "用户故事", "phase" => "评审阶段", "column" => "测试中", "period" => "本周", "time" => "14:30",
      "meeting" => "周计划会", "check" => "单元测试", "project" => "知识库项", "page" => "发布说明", "file" => "题" * 6,
      "title" => "题" * 6, "subject" => "题" * 6, "facts" => "题" * 6, "later" => "v2.0 团队版", "release" => "10/21（周三）",
      "who" => "Frank负责", "label" => "#1234", "added" => "Frank 今天把我加了进来", "set" => "按计划进行", "suggested" => "偏离计划"
    }
  end

  def worst(copy, overrides = {})
    values = longest.merge(overrides)
    copy.gsub(/%\{(\w+)\}/) do
      values.fetch(Regexp.last_match(1)) { raise "no longest value for %{#{Regexp.last_match(1)}} in #{copy}" }
    end
  end

  def sentences(prefix)
    value = I18n.t(prefix, locale: :"zh-CN")
    return [[prefix, value]] if value.is_a?(String)

    value.flat_map { |key, inner| sentences("#{prefix}.#{key}") if inner }.compact
  end

  def too_long(pairs, overrides = {})
    pairs.filter_map do |key, text|
      length = worst(text, overrides).length
      "#{key} (#{length}): #{text}" if length > limit
    end
  end

  it "stays within the limit in every detector" do
    headlines = I18n.t("assistant.proactive", locale: :"zh-CN").flat_map do |detector, keys|
      next [] unless keys.is_a?(Hash)

      keys.filter_map { |key, text| ["#{detector}.#{key}", text] if key.to_s.start_with?("headline") && text.is_a?(String) }
    end

    expect(headlines).not_to be_empty
    expect(too_long(headlines)).to be_empty
  end

  it "stays within the limit in the side notes at a decision" do
    pairs = %w[duplicate version_date project_status sprint_move].flat_map { sentences("assistant.aside.#{it}") }
    pairs += %w[deferred late].map do |key|
      ["assistant.aside.version_move.#{key}", I18n.t("assistant.aside.version_move.#{key}", locale: :"zh-CN")]
    end

    expect(too_long(pairs, "subject" => "题" * 14, "sprint" => "S" * 10)).to be_empty
  end

  it "shortens what a person wrote rather than the consequence when a main sentence runs over" do
    detector = Assistant::Proactive::Detectors::RepeatedQuestion.new(build_stubbed(:project))

    sentence = I18n.with_locale(:"zh-CN") { detector.send(:t, "headline", title: "很长的问题" * 12, count: 12) }

    expect(sentence.length).to be <= limit
    expect(sentence).to include("写进常见问题")
  end

  it "never shortens a person's name and cuts what they wrote at a punctuation mark" do
    detector = Assistant::Proactive::Detectors::IdleCapacity.new(build_stubbed(:project))

    sentence = I18n.with_locale(:"zh-CN") do
      detector.send(:t, "headline", name: "Sam Okafor", hours: "69.0", ref: "#101", subject: "接口文档说明，包含鉴权与限流的全部说明")
    end

    expect(sentence.length).to be <= limit
    expect(sentence).to start_with("Sam Okafor 有 69.0 小时空档")
    expect(sentence).not_to include("...")
    expect(sentence).to include("「接口文档说明…」")
  end
end
