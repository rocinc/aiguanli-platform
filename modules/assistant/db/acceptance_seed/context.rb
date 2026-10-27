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

module AssistantSeed
  PEOPLE = { ada: 30, sam: 31, frank: 32, fiona: 33, bob: 34, ben: 35, mia: 36, quinn: 37 }.freeze
  STATUSES = { new: 1, clarifying: 2, clear: 3, confirmed: 4, backlog: 5, planned: 6, doing: 7, devdone: 8, testing: 9,
               closed: 12, onhold: 13 }.freeze
  TYPES = { task: 1, milestone: 2, feature: 4, epic: 5, story: 6, bug: 7 }.freeze
  PRIORITIES = { low: 7, normal: 8, high: 9, urgent: 10 }.freeze
  ACTIVITIES = { manage: 1, requirements: 2, development: 3, testing: 4 }.freeze

  class Context
    attr_reader :today, :monday

    def initialize(today)
      @today = today
      @monday = today.beginning_of_week(:monday)
    end

    def d(offset) = monday + offset

    def weekday?(date) = date.cwday <= 5

    def forward(date) = weekday?(date) ? date : date + (8 - date.cwday)

    def backward(date) = weekday?(date) ? date : date - (date.cwday - 5)

    def at(day, hm)
      date = day.is_a?(Integer) ? backward(d(day)) : day
      Time.zone.parse("#{date} #{hm}")
    end

    def now = at(today, "09:02")

    def user(key) = (@users ||= {})[key] ||= User.find(PEOPLE.fetch(key))

    def admin = @admin ||= User.find_by!(login: "admin")

    def project = @project ||= Project.find_by!(identifier: "quill")

    def day_label(date) = "#{date.month}月#{date.day}日"

    def retime(journable, last, step = 2.days)
      journals = Journal.where(journable_type: journable.class.base_class.name, journable_id: journable.id).order(:version).to_a
      journals.each_with_index do |journal, index|
        stamp = last - ((journals.size - 1 - index) * step)
        following = index == journals.size - 1 ? nil : last - ((journals.size - 2 - index) * step)
        journal.update_columns(created_at: stamp, updated_at: stamp, validity_period: (stamp...following))
        Assistant::Event.where(journal_id: journal.id).update_all(created_at: stamp)
      end
    end

    def say(message) = puts("[seed] #{message}")
  end
end
