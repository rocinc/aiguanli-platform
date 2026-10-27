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
      # New work here that another project already did (03 §6.1 复用, 04 A1):
      # whoever owns it sees, on the work package itself, the finished work
      # elsewhere and who did it, with a ready question for that person and
      # a link between the two.
      class CrossProjectReuse < Base
        def candidates
          events("work_package.created").map(&:subject).uniq.filter_map do |wp|
            next unless wp.is_a?(WorkPackage) && Assistant::Facts.open?(wp)

            owner = Routing.owner_of(wp) or next
            match = Assistant::Facts::Elsewhere.new(project, wp.subject, viewer: owner, today:).matches.find(&:closed) or next
            build(wp, owner, match)
          end
        end

        private

        def build(wp, owner, match)
          other = match.work_package
          candidate(
            fingerprint: "#{wp.id}:#{other.id}", recipient: owner, subject: wp, nature: :opportunity, channel: "inline",
            headline: t("headline", project: other.project.name, ref: "##{other.id}"),
            because: [t("done", ref: "##{other.id}", subject: other.subject.truncate(50), project: other.project.name,
                                on: day(other.updated_at.to_date)),
                      (t("by", name: match.doer.name) if match.doer)].compact,
            impact: { people: 1 }, facts: { other_id: other.id, share: match.share },
            steps_for: ->(_user) { options(wp, other, match.doer, owner) }
          )
        end

        def options(wp, other, doer, owner)
          list = []
          if doer && doer != owner
            list << option(t("ask", name: doer.name), t("ask_consequence", project: other.project.name), "ask_elsewhere",
                           [comment(other, t("ask_comment", who: mention(doer), ref: "##{wp.id}", subject: wp.subject.truncate(60),
                                                            project: project.name))])
          end
          list << option(t("relate", ref: "##{other.id}"), t("relate_consequence"), "relate_elsewhere",
                         [{ "op" => "create_relation", "attributes" => { "from_id" => wp.id, "to_id" => other.id,
                                                                         "relation_type" => "relates" } }])
          list
        end
      end
    end
  end
end
