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
      # A work package was just created and one already in this project says
      # the same (04 A1 决策时刻：新建工作包时提示可能的重复). Whoever created
      # it sees, on the new one, the older one with its state and owner, and
      # can mark it a duplicate (the platform's "duplicates" relation) in one go.
      class PossibleDuplicate < Base
        def candidates
          events("work_package.created").uniq(&:subject_id).filter_map do |event|
            wp = event.subject
            next unless wp.is_a?(WorkPackage) && Assistant::Facts.open?(wp)

            creator = event.actor
            next unless creator.is_a?(User) && creator.active? && !creator.is_a?(AssistantUser)

            found = best_match(wp) or next
            next if Assistant::Signal.exists?(recipient: creator, detector: self.class.key, 
                                              fingerprint: "draft:#{found.first.id}")

            build(wp, creator, *found)
          end
        end

        private

        def best_match(wp)
          related = Relation.where(from_id: wp.id).pluck(:to_id) + Relation.where(to_id: wp.id).pluck(:from_id)
          Assistant::Facts::SimilarSubjects.find(project:, type_id: wp.type_id, subject: wp.subject,
                                                 except: [wp.id, *related, *wp.ancestors.pluck(:id)]).first
        end

        def build(wp, creator, other, share)
          candidate(
            fingerprint: "#{wp.id}:#{other.id}", recipient: creator, subject: wp, nature: :own, channel: "inline",
            headline: t("headline", ref: "##{other.id}"),
            because: [t("other", ref: "##{other.id}", subject: other.subject.truncate(60), status: other.status.name,
                                 name: other.assigned_to&.name || t("nobody")),
                      t("share", percent: (share * 100).round)],
            impact: { people: 1 }, facts: { other_id: other.id, share: },
            steps_for: ->(_user) { options(wp, other) }
          )
        end

        def options(wp, other)
          [option(t("duplicate", ref: "##{other.id}"), t("duplicate_consequence"), "mark_duplicate",
                  [{ "op" => "create_relation",
                     "attributes" => { "from_id" => wp.id, "to_id" => other.id, "relation_type" => "duplicates" } }]),
           option(t("relate", ref: "##{other.id}"), t("relate_consequence"), "relate_similar",
                  [{ "op" => "create_relation",
                     "attributes" => { "from_id" => wp.id, "to_id" => other.id, "relation_type" => "relates" } }])]
        end
      end
    end
  end
end
