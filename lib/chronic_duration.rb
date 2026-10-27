# Copied from https://gitlab.com/gitlab-org/ruby/gems/gitlab-chronic-duration
# version 0.12.0
#
# Copyright (c) Henry Poydar
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use,
# copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following
# conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.

# NOTE:
# Changes to this file should be kept in sync with
# frontend/src/app/shared/helpers/chronic_duration.js.

module ChronicDuration
  extend self

  class DurationParseError < StandardError
  end

  # On average, there's a little over 4 weeks in month.
  FULL_WEEKS_PER_MONTH = 4

  # 365.25 days in a year.
  SECONDS_PER_YEAR = 31_557_600

  @@raise_exceptions = false
  @@hours_per_day = 24
  @@days_per_month = 30

  def self.raise_exceptions
    !!@@raise_exceptions
  end

  def self.raise_exceptions=(value)
    @@raise_exceptions = !!value
  end

  def self.hours_per_day
    @@hours_per_day
  end

  def self.hours_per_day=(value)
    @@hours_per_day = value
  end

  def self.days_per_month
    @@days_per_month
  end

  def self.days_per_month=(value)
    @@days_per_month = value
  end

  # Given a string representation of elapsed time,
  # return an integer (or float, if fractions of a
  # second are input)
  def parse(string, opts = {})
    result = calculate_from_words(cleanup(string, opts), opts)
    !opts[:keep_zero] && result == 0 ? nil : result
  end

  # Given an integer and an optional format,
  # returns a formatted string representing elapsed time
  # rubocop:disable Lint/UselessAssignment
  def output(seconds, opts = {}) # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
    int = seconds.to_i
    seconds = int if seconds - int == 0 # if seconds end with .0

    opts[:format] ||= :default
    opts[:keep_zero] ||= false

    hours_per_day = opts[:hours_per_day] || ChronicDuration.hours_per_day
    days_per_month = opts[:days_per_month] || ChronicDuration.days_per_month
    days_per_week = days_per_month / FULL_WEEKS_PER_MONTH

    years = months = weeks = days = hours = minutes = 0

    decimal_places = seconds.to_s.split(".").last.length if seconds.is_a?(Float)

    minute = 60
    hour = 60 * minute
    day = hours_per_day * hour
    month = days_per_month * day
    year = SECONDS_PER_YEAR

    if %i[hours_only hours_and_minutes].include?(opts[:format])
      hours = seconds / 3600.0
      seconds = 0
    elsif opts[:format] == :hours_colon_minutes
      hours = (seconds / hour).to_i
      minutes = (seconds % hour / minute).to_i
      minutes += 1 if (seconds % hour % minute) > 0
      seconds = 0
    elsif seconds >= SECONDS_PER_YEAR && seconds % year < seconds % month
      years = seconds / year
      months = seconds % year / month
      days = seconds % year % month / day
      hours = seconds % year % month % day / hour
      minutes = seconds % year % month % day % hour / minute
      seconds = seconds % year % month % day % hour % minute
    elsif seconds >= 60
      minutes = (seconds / 60).to_i
      seconds %= 60
      if minutes >= 60
        hours = (minutes / 60).to_i
        minutes = (minutes % 60).to_i
        if !opts[:limit_to_hours] && (hours >= hours_per_day)
          days = (hours / hours_per_day).to_i
          hours = (hours % hours_per_day).to_i
          if opts[:weeks]
            if days >= days_per_week
              weeks = (days / days_per_week).to_i
              days = (days % days_per_week).to_i
              if weeks >= FULL_WEEKS_PER_MONTH
                months = (weeks / FULL_WEEKS_PER_MONTH).to_i
                weeks = (weeks % FULL_WEEKS_PER_MONTH).to_i
              end
            end
          elsif days >= days_per_month
            months = (days / days_per_month).to_i
            days = (days % days_per_month).to_i
          end
        end
      end
    end

    joiner = opts.fetch(:joiner) { " " }
    process = nil

    case opts[:format]
    when :micro
      dividers = {
        years: "y", months: "mo", weeks: "w", days: "d", hours: "h", minutes: "m", seconds: "s"
      }
      joiner = ""
    when :short
      dividers = {
        years: "y", months: "mo", weeks: "w", days: "d", hours: "h", minutes: "m", seconds: "s"
      }
    when :default
      dividers = {
        years: " yr", months: " mo", weeks: " wk", days: " day", hours: " hr", minutes: " min", seconds: " sec",
        pluralize: true
      }
    when :long
      dividers = {
        years: " year", months: " month", weeks: " week", days: " day", hours: " hour", minutes: " minute", seconds: " second",
        pluralize: true
      }
    when :days_and_hours
      dividers = {
        hours: "h", keep_zero: true
      }

      days += weeks * days_per_week
      days += months * days_per_month
      days += years * SECONDS_PER_YEAR / 3600 / 24
      dividers[:days] = "d" if days > 0
      years = months = weeks = 0

      hours = (hours + (((minutes * 60) + seconds) / 3600.0)).round(2)
      hours_int = hours.to_i
      hours = hours_int if hours - hours_int == 0 # if hours end with .0
      minutes = seconds = 0
    when :hours_only
      dividers = {
        hours: "h", keep_zero: true
      }

      hours = hours.round(2)
      hours_int = hours.to_i
      hours = hours_int if hours - hours_int == 0 # if hours end with .0
    when :hours_and_minutes
      dividers = { hours: "h", minutes: "m", keep_zero: false }

      minutes = ((hours % 1) * 60).round
      hours = hours.floor
    when :hours_colon_minutes
      dividers = {
        hours: ":", minutes: "", keep_zero: true
      }
      process = lambda do |str|
        # Pad zeros on minutes
        divider = ":"
        result = str.split(divider).each_with_index.map do |n, index|
          n.rjust(index > 0 ? 2 : 1, "0")
        end.join(divider)
        "#{result} h"
      end
      joiner = ""
    when :chrono
      dividers = {
        years: ":", months: ":", weeks: ":", days: ":", hours: ":", minutes: ":", seconds: ":", keep_zero: true
      }
      process = lambda do |str|
        # Pad zeros
        # Get rid of lead off times if they are zero
        # Get rid of lead off zero
        # Get rid of trailing :
        divider = ":"
        str.split(divider).map do |n|
          # add zeros only if n is an integer
          n.include?(".") ? ("%04.#{decimal_places}f" % n) : ("%02d" % n)
        end.join(divider).gsub(/^(00:)+/, "").gsub(/^0/, "").gsub(/:$/, "")
      end
      joiner = ""
    end

    result = %i[years months weeks days hours minutes seconds].map do |t|
      next if t == :weeks && !opts[:weeks]

      num = eval(t.to_s) # rubocop:disable Security/Eval
      num = ("%.#{decimal_places}f" % num) if num.is_a?(Float) && t == :seconds
      keep_zero = dividers[:keep_zero]
      keep_zero ||= opts[:keep_zero] if t == :seconds
      humanize_time_unit(num, dividers[t], dividers[:pluralize], keep_zero)
    end.compact!

    result = result[0...opts[:units]] if opts[:units]

    result = result.join(joiner)

    result = process.call(result) if process

    result.empty? ? nil : result
  end
  # rubocop:enable Lint/UselessAssignment

  private

  def humanize_time_unit(number, unit, pluralize, keep_zero)
    return nil if number == 0 && !keep_zero
    return unless unit

    res = "#{number}#{unit}"
    # A poor man's pluralizer
    res << "s" if (number != 1) && pluralize
    res
  end

  def calculate_from_words(string, opts) # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
    val = 0
    last_explicit_unit = nil
    words = string.split

    words.each_with_index do |v, k|
      next unless v&.match?(float_matcher)

      next_word = words[k + 1]

      if next_word && duration_units_list.include?(next_word)
        # Next word is a valid unit, use it and remember as last explicit unit
        unit = next_word
        last_explicit_unit = next_word
      elsif last_explicit_unit
        # No explicit unit, but we have a previous unit - use next smaller unit
        current_index = duration_units_list.index(last_explicit_unit)
        unit = if current_index > 0
                 # Use next smaller unit (lower index in array)
                 duration_units_list[current_index - 1]
               else
                 # Already at smallest unit (seconds), keep using it
                 last_explicit_unit
               end
        last_explicit_unit = unit
      else
        # No explicit unit and no previous unit, fall back to default
        unit = opts[:default_unit] || "seconds"
      end

      val += convert_to_number(v) * duration_units_seconds_multiplier(unit, opts)
    end
    val
  end

  def cleanup(string, opts = {})
    res = string.downcase
    res = filter_by_type(res)
    res = res.gsub(float_matcher) { |n| " #{n} " }.squeeze(" ").strip
    filter_through_white_list(res, opts)
  end

  def convert_to_number(string)
    string.to_f % 1 > 0 ? string.to_f : string.to_i
  end

  def duration_units_list
    %w[seconds minutes hours days weeks months years]
  end

  def duration_units_seconds_multiplier(unit, opts)
    return 0 unless duration_units_list.include?(unit)

    hours_per_day = opts[:hours_per_day] || ChronicDuration.hours_per_day
    days_per_month = opts[:days_per_month] || ChronicDuration.days_per_month
    days_per_week = days_per_month / FULL_WEEKS_PER_MONTH

    case unit
    when "years" then   31_557_600
    when "months" then  3600 * hours_per_day * days_per_month
    when "weeks" then   3600 * hours_per_day * days_per_week
    when "days" then    3600 * hours_per_day
    when "hours" then   3600
    when "minutes" then 60
    when "seconds" then 1
    end
  end

  # Parse 3:41:59 and return 3 hours 41 minutes 59 seconds
  def filter_by_type(string) # rubocop:disable Metrics/AbcSize
    chrono_units_list = duration_units_list.reject { |v| v == "weeks" }

    if string.delete(" ")&.match?(time_matcher)
      res = []
      string.delete(" ").split(":").reverse.each_with_index do |v, k|
        return unless chrono_units_list[k] # rubocop:disable Lint/NonLocalExitFromIterator

        res << "#{v} #{chrono_units_list[k]}"
      end
      res = res.reverse.join(" ")
    else
      res = string
    end
    res
  end

  def time_matcher
    /^[0-9]+:[0-9]+(:[0-9]+){0,4}(\.[0-9]*)?$/
  end

  def float_matcher
    /[0-9]*\.?[0-9]+/
  end

  # Get rid of unknown words and map found
  # words to defined time units
  def filter_through_white_list(string, opts) # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
    res = []
    string.split.each do |word|
      if word&.match?(float_matcher)
        res << word.strip
        next
      end
      stripped_word = word.strip.gsub(/^,/, "").gsub(/,$/, "")
      if mappings.has_key?(stripped_word)
        res << mappings[stripped_word]
      elsif !join_words.include?(stripped_word) and opts.fetch(:raise_exceptions, ChronicDuration.raise_exceptions) # rubocop:disable Rails/NegateInclude
        raise DurationParseError, "An invalid word #{word.inspect} was used in the string to be parsed."
      end
    end
    # add '1' at front if string starts with something recognizable but not with a number, like 'day' or 'minute 30sec'
    res.unshift(1) if !res.empty? && mappings[res[0]]
    res.join(" ")
  end

  def mappings
    {
      "seconds" => "seconds",
      "second" => "seconds",
      "secs" => "seconds",
      "sec" => "seconds",
      "s" => "seconds",
      "minutes" => "minutes",
      "minute" => "minutes",
      "mins" => "minutes",
      "min" => "minutes",
      "m" => "minutes",
      "hours" => "hours",
      "hour" => "hours",
      "hrs" => "hours",
      "hr" => "hours",
      "h" => "hours",
      "days" => "days",
      "day" => "days",
      "dy" => "days",
      "d" => "days",
      "weeks" => "weeks",
      "week" => "weeks",
      "wks" => "weeks",
      "wk" => "weeks",
      "w" => "weeks",
      "months" => "months",
      "mo" => "months",
      "mos" => "months",
      "month" => "months",
      "years" => "years",
      "year" => "years",
      "yrs" => "years",
      "yr" => "years",
      "y" => "years"
    }
  end

  def join_words
    %w[and with plus]
  end
end
