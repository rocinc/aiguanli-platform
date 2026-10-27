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
  # What the assistant answered where there is no thread to answer in (an
  # agenda item's notes): first its sentence, folded over the rest of the
  # answer, and the way to the conversation. While it works, only the line
  # saying it heard.
  class AnswerLineComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    STALE_AFTER = 1.day

    def initialize(signal:, user:)
      super()
      @signal = signal
      @user = user
    end

    attr_reader :signal, :user

    def self.for?(signal) = signal.detector == "mention_answer" && signal.payload["source_gid"].present?

    def render? = holding? || signal.created_at > STALE_AFTER.ago

    def holding? = signal.payload["holding"].present?

    def headline = signal.headline

    def rest = signal.payload["answer"].to_s.lines.drop(1).join.strip

    def rest_html = helpers.format_text(rest, project: signal.project, only_path: true)

    def conversation_id = signal.options.filter_map { it["conversation_id"] }.first
  end
end
