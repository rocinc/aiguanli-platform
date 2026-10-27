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
  module Proactive
    module Detectors
      # "要是能……就好了", "以后可以考虑……": an idea said in passing is kept in
      # the project's idea garden with who said it where, not as a to-do. When
      # a second or third person says the same thing, whoever plans hears so
      # in the brief, with a way to turn it into a work package.
      class IdeaGarden < Base
        PATTERNS = [/要是能(.{2,40}?)(?:就好了|该多好|多好)/, /(?:以后|将来|后续)可以考虑(.{2,40})/, /其实还有一种(?:做法|办法|思路)[，,：:]?(.{2,40})/,
                    /(?:能不能|可不可以|是否可以)(?:以后|将来)?(.{2,30})(?:\?|？)/, /it would be (?:nice|great) (?:if|to) (.{3,60})/i,
                    /(?:we|you) could (?:also )?(?:consider|try) (.{3,60})/i].freeze
        ASKING = /(?<!邀)请|帮我|帮忙|麻烦|给我|替我|发给我|(?:周|星期)[一二三四五六日天]前|\d+[点号日]前|please|can you|could you/i
        SAME_IDEA = 0.5

        def self.work_package_steps(idea, user)
          entry = Assistant::Ideas::Entry.new(idea, user)
          [{ "op" => "create_work_package",
             "attributes" => { "project_id" => idea.project_id, "subject" => (entry.title || idea.title).truncate(200),
                               "description" => entry.work_package_description } }]
        end

        def candidates
          harvest!
          Assistant::Idea.open.where(project:).includes(:mentions).filter_map do |idea|
            speakers = idea.mentions.map(&:speaker_id).compact.uniq
            next if speakers.size < 2

            lead = leads.first or next
            candidate(
              fingerprint: "#{idea.id}:#{speakers.size}", recipient: lead, subject: project, nature: :opportunity,
              channel: "brief",
              headline: t("headline", title: idea.title.truncate(40), count: speakers.size),
              because: idea.mentions.first(4).map do
                t("mention", name: it.speaker&.name || "–", quote: it.quote.truncate(60), on: day(it.said_at.to_date))
              end,
              facts: { idea_id: idea.id },
              steps_for: ->(user) {
                [option(t("make_work_package"), t("make_work_package_consequence"), "idea_to_work_package",
                        self.class.work_package_steps(idea, user))]
              }
            )
          end
        end

        private

        def harvest!
          Journal.where(journable_type: "WorkPackage", journable_id: WorkPackage.where(project:).select(:id))
                 .where(created_at: since..).where.not(notes: [nil, ""]).where.not(user_id: Assistant.user.id)
                 .find_each { collect(it, Assistant::Text.plain(it.notes), it.user_id, it.created_at) }
        end

        def collect(source, text, speaker_id, at)
          PATTERNS.each do |pattern|
            text.scan(pattern).flatten.compact.each do |phrase|
              phrase = phrase.strip.delete_suffix("。").delete_suffix(".")
              next if phrase.length < 2

              quote = text[/[^。！？.!?\n]*#{Regexp.escape(phrase)}[^。！？.!?\n]*/] || phrase
              next if quote.match?(ASKING)

              idea = similar(phrase) || Assistant::Idea.create!(project:, title: phrase.truncate(120))
              next if idea.mentions.exists?(source:)

              idea.mentions.create!(speaker_id:, source:, quote: quote.strip.truncate(500), said_at: at)
            end
          end
        end

        def similar(phrase)
          Assistant::Idea.open.where(project:).find do |idea|
            share, = Assistant::Text.overlap("#{idea.title} #{idea.mentions.map(&:quote).join(' ')}", phrase)
            share >= SAME_IDEA
          end
        end
      end
    end
  end
end
