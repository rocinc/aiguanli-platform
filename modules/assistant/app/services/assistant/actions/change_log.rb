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
  module Actions
    # What a step did to each record, over every save the platform made of it: a
    # record's own `saved_changes` only remember the last one, and scheduling
    # saves a work package again after the date that was asked for.
    module ChangeLog
      KEY = :assistant_change_log
      IGNORED = %w[updated_at lock_version created_at].freeze

      Entry = Struct.new(:changes, :created)

      module_function

      def capture
        outer = Thread.current[KEY]
        Thread.current[KEY] = {}
        yield
      ensure
        Thread.current[KEY] = outer
      end

      def saved(record)
        log = Thread.current[KEY] or return

        entry = log[key(record)] ||= Entry.new({}, false)
        record.saved_changes.except(*IGNORED).each do |attribute, (from, to)|
          entry.changes[attribute] = entry.changes.key?(attribute) ? [entry.changes[attribute].first, to] : [from, to]
        end
        entry.created ||= record.previously_new_record?
      end

      def entry_for(record)
        entry = Thread.current[KEY]&.[](key(record)) or return

        Entry.new(entry.changes.reject { |_, (from, to)| from == to }, entry.created)
      end

      def key(record) = [record.class.base_class.name, record.id]
    end
  end
end
