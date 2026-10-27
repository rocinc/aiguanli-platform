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
  # "6 h left this week" or "Away until 10/20" beside a person's name. In a
  # list of choices it is always said; in a line of text, only when it would
  # change what you do with the person (away, or nothing left).
  class PersonLoadHintComponent < ApplicationComponent
    def initialize(person:, today: Date.current, reading: nil, always: true)
      super()
      @person = person
      @today = today
      @reading = reading
      @always = always
    end

    attr_reader :person

    def reading = @reading ||= Assistant::PersonLoad.of(person, today: @today)

    def render? = person.is_a?(User) && !person.is_a?(AssistantUser) && text.present?

    def call
      content_tag(:span, text, class: "assistant-person-load", data: { test_selector: "assistant-person-load" })
    end

    def text
      return t("assistant.verbs.panel.assign.away", date: I18n.l(reading.away_until, format: "%-m/%-d")) if reading.away_until
      return unless @always || reading.free_hours.zero?

      t("assistant.verbs.panel.assign.free", hours: Assistant::Text.hours(reading.free_hours))
    end
  end
end
