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
  # A translated sentence with people in it, where each name is a link that
  # opens the person's hover card. A person who is not there (or may not be
  # named) is passed as nil and the sentence is expected to have a variant
  # without the name.
  module PersonInText
    MARK = "\u0001"

    module_function

    def call(view, key, people, **plain)
      marks = people.keys.index_with { "#{MARK}#{it}#{MARK}" }
      parts = I18n.t(key, **plain, **marks).split(/#{MARK}(\w+)#{MARK}/)
      view.safe_join(parts.each_with_index.map { |part, index| index.odd? ? person(view, people.fetch(part.to_sym)) : part })
    end

    def person(view, person)
      return person.try(:name) || person unless person.is_a?(User) && !person.is_a?(AssistantUser)

      helpers = view.helpers
      helpers.link_to(person.name, helpers.user_path(person),
                      data: { turbo_frame: "_top", hover_card_url: helpers.hover_card_user_path(person),
                              hover_card_trigger_target: "trigger" })
    end
  end
end
