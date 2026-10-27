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

module Assistant
  module Text
    module_function

    def plain(markup)
      return "" if markup.blank?

      fragment = Nokogiri::HTML::DocumentFragment.parse(markup.to_s)
      fragment.css("mention").each { |node| node.replace("@#{node.text.delete_prefix('@')}") }
      fragment.css("br").each { |node| node.replace("\n") }
      fragment.text.gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip
    end

    # "9/30（周三）": the weekday is there because a working day gone wrong is
    # easiest to see in it. The year only appears when it is not this one.
    def day(date)
      date = date.to_date
      stamp = I18n.l(date, format: date.year == Date.current.year ? "%-m/%-d" : "%Y/%-m/%-d")
      I18n.t("assistant.text.day", date: stamp, weekday: I18n.t("date.abbr_day_names")[date.wday])
    end

    # Hours as a person says them: to the half hour, no trailing ".0".
    def hours(value)
      half = (value.to_f * 2).round / 2.0
      half == half.to_i ? half.to_i.to_s : half.to_s
    end

    def first_name(user) = user.try(:firstname).presence || user.name

    def moment(time)
      time = time.in_time_zone
      I18n.t("assistant.text.moment", day: day(time.to_date), time: time.strftime("%H:%M"))
    end

    def stamp(time)
      time = time.in_time_zone
      case time.to_date
      when Date.current then I18n.t("assistant.text.today", time: time.strftime("%H:%M"))
      when Date.current - 1 then I18n.t("assistant.text.yesterday", time: time.strftime("%H:%M"))
      else day(time.to_date)
      end
    end

    def normalize(text) = text.to_s.gsub(/\s+/, "").unicode_normalize(:nfkc)

    # Character bigrams for CJK runs, whole lowercase words for everything
    # else. Short Chinese titles share almost no trigrams even when they name
    # the same thing; bigrams are what the two phrasings actually have in common.
    FUNCTION_CHARS = "的了吗吧呢啊呀是不没要能会就也都还在有和与或把被给让改成这那个么什怎如何吗否请".chars.to_set.freeze

    TIME_WORDS = %w[本迭代 下迭代 迭代 冲刺 下版 本周 下周 今天 明天 后天 周一 周二 周三 周四 周五 月底 sprint].freeze

    # The tokens a text is about: `tokens` without the bigrams that are only
    # there because of grammar ("要不", "改成"), and without time expressions,
    # which say when rather than what.
    def terms(text)
      timeless = TIME_WORDS.reduce(text.to_s.downcase) { |rest, word| rest.gsub(word, " ") }
      tokens(timeless).reject do |token|
        token.match?(/\p{Han}/) && token.chars.any? { |char| FUNCTION_CHARS.include?(char) }
      end.to_set
    end

    def tokens(text)
      text.to_s.unicode_normalize(:nfkc).downcase.scan(/\p{Han}+|[a-z0-9]+/).flat_map do |run|
        next [] if run.length == 1
        next [run] unless run.match?(/\p{Han}/)

        run.chars.each_cons(2).map(&:join)
      end.to_set
    end

    # How much of `shorter` is found in `longer`, and how many tokens that is.
    def overlap(longer, shorter)
      a = tokens(longer)
      b = tokens(shorter)
      shared = (a & b).size
      [b.empty? ? 0.0 : shared.fdiv(b.size), shared]
    end

    def contains?(haystack, needle)
      needle = normalize(needle)
      needle.length >= 2 && normalize(haystack).include?(needle)
    end
  end
end
