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
      # A question here that has waited, and someone in another project who
      # did that very thing (03 §6.1 连接人). Nobody in one team sees across
      # teams; the asker gets the name, what they did, and a ready note to
      # them on their own work package.
      class Matchmaker < Base
        WINDOW = 30.days
        WAITING_WORKING_DAYS = 2

        def candidates
          members = Routing.people(project).map(&:id).to_set
          questions.filter_map do |question|
            asker = question.owner
            next unless asker.is_a?(User) && asker.active?

            match = Assistant::Facts::Elsewhere.new(project, "#{question.title} #{question.quote}", viewer: asker, today:)
                                               .matches(limit: 5).find { it.doer && !members.include?(it.doer.id) } or next
            build(question, asker, match)
          end
        end

        private

        def questions
          waited = Assistant::Facts.add_working_days(today, -WAITING_WORKING_DAYS).end_of_day
          Assistant::Intent.where(project:, kind: "question", status: "open").where(stated_at: WINDOW.ago..waited)
                            .includes(:owner, :subject).to_a
        end

        def build(question, asker, match)
          other = match.work_package
          candidate(
            fingerprint: "q#{question.id}:#{match.doer.id}", recipient: asker, subject: page_top(question.subject), nature: :opportunity,
            channel: "inline",
            headline: t("headline", name: match.doer.name, project: other.project.name, title: question.title.truncate(40)),
            because: [t("asked", on: day(question.stated_at.to_date), quote: question.quote.truncate(60)),
                      t("did", name: match.doer.name, ref: "##{other.id}", subject: other.subject.truncate(50),
                               project: other.project.name)],
            impact: { people: 2 }, facts: { other_id: other.id, user_id: match.doer.id },
            steps_for: ->(_user) { [ask_option(question, other, match.doer)] }
          )
        end

        def ask_option(question, other, doer)
          where = question.subject.is_a?(WorkPackage) ? "##{question.subject_id}" : project.name
          option(t("ask", name: doer.name), t("ask_consequence"), "ask_elsewhere",
                 [comment(other, t("ask_comment", who: mention(doer), quote: question.quote.truncate(120), where:,
                                                  project: project.name))])
        end
      end
    end
  end
end
