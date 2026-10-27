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
  module Facts
    # Who knows about a topic: the people who did, logged time on, or wrote
    # about the work packages and wiki pages that match it, weighted by how
    # much of the matching work was theirs.
    class Expertise
      WEIGHTS = { "assigned" => 3.0, "hours" => 0.25, "comment" => 1.0, "wiki" => 2.0 }.freeze
      MIN_MATCH = 0.34

      Person = Data.define(:user, :score, :evidence)

      def initialize(project, topic, viewer:)
        @project = project
        @topic = topic.to_s
        @viewer = viewer
      end

      def people(limit: 5)
        scores = Hash.new { |h, k| h[k] = { score: 0.0, evidence: [] } }

        matching_work_packages.each do |wp, share|
          if wp.assigned_to_id
            add(scores, wp.assigned_to_id, WEIGHTS["assigned"] * share, I18n.t("assistant.facts.expertise.did", ref: "##{wp.id}"))
          end
          hours_on(wp).each do |user_id, hours|
            add(scores, user_id, WEIGHTS["hours"] * hours * share,
                I18n.t("assistant.facts.expertise.logged", hours: [hours.round, 1].max, ref: "##{wp.id}"))
          end
          commenters_on(wp).each do |user_id, count|
            add(scores, user_id, WEIGHTS["comment"] * count * share,
                I18n.t("assistant.facts.expertise.wrote", count:, ref: "##{wp.id}"))
          end
        end
        matching_wiki_pages.each do |page, share|
          page.journals.reorder(nil).distinct.pluck(:user_id).each do |user_id|
            add(scores, user_id, WEIGHTS["wiki"] * share, I18n.t("assistant.facts.expertise.wiki", title: page.title))
          end
        end

        users = User.where(id: scores.keys).where.not(type: "AssistantUser").index_by(&:id)
        scores.filter_map do |id, s|
          users[id] && Person.new(user: users[id], score: s[:score].round(1), evidence: s[:evidence].uniq.first(4))
        end
              .sort_by { -it.score }.first(limit)
      end

      private

      def add(scores, user_id, score, evidence)
        scores[user_id][:score] += score
        scores[user_id][:evidence] << evidence
      end

      def matching_work_packages
        @matching_work_packages ||= WorkPackage.visible(@viewer).where(project: @project).includes(:journals).filter_map do |wp|
          said = wp.journals.filter_map { it.notes.presence && Assistant::Text.plain(it.notes) }.join(" ")
          share = match("#{wp.subject} #{Assistant::Text.plain(wp.description).first(300)} #{said}", wp.subject)
          [wp, share] if share >= MIN_MATCH
        end
      end

      def matching_wiki_pages
        return [] unless @project.wiki && @viewer.allowed_in_project?(:view_wiki_pages, @project)

        @project.wiki.pages.filter_map do |page|
          share = match("#{page.title} #{page.text.to_s.first(300)}", page.title)
          [page, share] if share >= MIN_MATCH
        end
      end

      # A short topic ("PDF 导出") is matched by how much of it the work
      # mentions; a long one (a whole forum post) by how much of the work's
      # title it mentions.
      def match(text, title = nil)
        share, = Assistant::Text.overlap(text.to_s, @topic)
        return share if title.blank?

        [share, Assistant::Text.overlap(@topic, title.to_s).first].max
      end

      def hours_on(wp) = TimeEntry.where(entity: wp).group(:user_id).sum(:hours)

      def commenters_on(wp) = wp.journals.reorder(nil).where.not(notes: [nil, ""]).group(:user_id).count
    end
  end
end
