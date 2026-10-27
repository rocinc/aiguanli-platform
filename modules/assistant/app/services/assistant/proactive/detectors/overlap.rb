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
      # Two people doing what reads like the same thing (03 §6.1 重叠): open
      # work packages with different assignees whose titles say the same, or
      # two wiki pages on one topic. Told to both people, early, on their own
      # work package or page, with a link between the two so they find each other.
      class Overlap < Base
        RECENT = 30.days
        MIN_MATCH = 70

        def candidates
          (work_package_pairs + page_pairs).flat_map do |one, other, share|
            [[one, other], [other, one]].filter_map do |mine, theirs|
              person = owner_of(mine)
              build(person, mine, theirs, share) if human?(person)
            end
          end
        end

        private

        def same(a, b)
          share = [Assistant::Text.overlap(a, b).first, Assistant::Text.overlap(b, a).first].min
          share if share >= MIN_MATCH.fdiv(100)
        end

        # Each pair once: one of the two is recent, the other may be older.
        def work_package_pairs
          assigned = open_work_packages.select(&:assigned_to_id)
          recent = assigned.select { it.created_at >= RECENT.ago }
          related = Relation.where(from_id: assigned.map(&:id)).or(Relation.where(to_id: assigned.map(&:id)))
                            .pluck(:from_id, :to_id).flat_map { [it, it.reverse] }.to_set
          recent.flat_map do |wp|
            assigned.filter_map do |other|
              next if other.id == wp.id || other.assigned_to_id == wp.assigned_to_id || related.include?([wp.id, other.id])
              next if recent.include?(other) && other.id < wp.id
              next if wp.ancestors.include?(other) || other.ancestors.include?(wp)

              share = same(wp.subject, other.subject) or next
              [wp, other, share]
            end
          end
        end

        def page_pairs
          pages = project.wiki ? project.wiki.pages.includes(:author).to_a : []
          recent = pages.select { it.updated_at >= RECENT.ago }
          recent.flat_map do |page|
            pages.filter_map do |other|
              next if other.id == page.id || other.author_id == page.author_id || (recent.include?(other) && other.id < page.id)
              next if page.text.to_s.include?(other.title) || other.text.to_s.include?(page.title)

              share = same(page.title, other.title) or next
              [page, other, share]
            end
          end
        end

        def owner_of(record) = record.is_a?(WorkPackage) ? record.assigned_to : record.author

        def build(person, one, other, share)
          candidate(
            fingerprint: [one, other].map { "#{it.class.name.demodulize}#{it.id}" }.sort.join(":"), recipient: person,
            subject: one, nature: :opportunity, channel: "inline",
            headline: t("headline", one: label(one), other: label(other)),
            because: [line(one), line(other), t("share", percent: (share * 100).round)],
            impact: { people: 2 }, facts: { share: },
            steps_for: ->(_user) { [link_option(one, other)] }
          )
        end

        def label(record) = record.is_a?(WorkPackage) ? "##{record.id}" : "“#{record.title.truncate(30)}”"

        def line(record)
          if record.is_a?(WorkPackage)
            t("work", ref: "##{record.id}", subject: record.subject.truncate(50), name: record.assigned_to&.name || "–")
          else
            t("page", title: record.title.truncate(50), name: record.author&.name || "–", on: day(record.updated_at.to_date))
          end
        end

        def link_option(one, other)
          if one.is_a?(WorkPackage)
            option(t("relate"), t("relate_consequence", one: one.assigned_to&.name, other: other.assigned_to&.name), "relate_overlap",
                   [{ "op" => "create_relation", "attributes" => { "from_id" => one.id, "to_id" => other.id, "relation_type" => "relates" } },
                    comment(one, t("comment", who: [one.assigned_to, other.assigned_to].compact.map { mention(it) }.join(" "),
                                              ref: "##{other.id}"))])
          else
            option(t("see_also", title: other.title.truncate(30)), t("see_also_consequence"), "link_pages",
                   [{ "op" => "create_wiki_page",
                      "attributes" => { "project_id" => project.id, "title" => one.title,
                                        "text" => "#{one.text}\n\n#{t('see_also_text', title: other.title)}",
                                        "notes" => t("see_also_notes", title: other.title) } }])
          end
        end
      end
    end
  end
end
