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
  module Appraisals
    # A first draft of the written appraisal: strengths, what could improve,
    # the situation, concrete examples. Every sentence rests on the profile;
    # the appraiser edits it before it is final.
    class Narrative
      SYSTEM = <<~PROMPT
        You draft a written appraisal of one team member for their manager, from the computed profile
        given as JSON. Write in the language given. Four short sections with headings: strengths,
        what could improve, situation (blocked time, absences, firefighting, early renegotiations —
        these are not held against the person), examples. Every claim must come from the profile and
        cite its number or work package (#id). Where a dimension says insufficient, say there is not
        enough data instead of judging. Renegotiating a date early counts in the person's favour.
        Neutral, specific, fair. Describe the work and the numbers, never the person: no traits or
        labels (careless, slow, reliable) — say what happened, e.g. "#69 was estimated at 3 days and took 6".
        No praise words without a number behind them. 150–300 words.
        Answer as JSON: {"text": "..."}.
      PROMPT

      def initialize(profile, author:, llm: nil)
        @profile = profile
        @author = author
        @llm = llm
      end

      def draft
        data = llm.json(system: SYSTEM, user: "Language: #{I18n.locale}\n\n#{JSON.generate(@profile.to_h)}", max_tokens: 3000)
        data["text"].to_s.strip
      end

      def save_draft!
        text = draft
        Assistant::Appraisal.create!(subject: @profile.user, project: @profile.project, author: @author,
                                     period_start: @profile.from, period_end: @profile.to,
                                     metrics: @profile.to_h, narrative: text)
      end

      private

      def llm = @llm ||= Assistant::Llm.new(purpose: "appraisal", user: @author, project: @profile.project)
    end
  end
end
