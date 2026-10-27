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
      # A decision that rests on little: someone questioned it and nobody
      # answered, or it was made by one person alone with no data quoted.
      # Before it takes effect, whoever made it is offered a cheap check —
      # ask the doubter, or plan a small validation (03 §6.3).
      class WeakDecision < Base
        DATA_HINT = /\d|样本|测试|数据|实验|评测|test|sample|data|benchmark/i

        def candidates
          Assistant::Intent.where(project:, kind: "decision", status: "active").where(stated_at: 45.days.ago..)
                            .includes(:owner, :subject, :source).filter_map do |decision|
            reasons = weaknesses(decision)
            next if reasons.empty? || !decision.owner.is_a?(User)

            candidate(
              fingerprint: "#{decision.id}:#{reasons.size}", recipient: decision.owner, subject: page_top(decision.subject),
              nature: :decision, channel: "inline", certainty: :fact,
              headline: t("headline", title: decision.title.truncate(40)),
              because: [t("decision", quote: decision.quote.truncate(60), on: day(decision.stated_at.to_date)), *reasons.map(&:first)],
              impact: { people: 2 }, facts: { why: "owns" },
              steps_for: ->(_user) { options(decision, reasons) }
            )
          end
        end

        private

        def weaknesses(decision)
          list = []
          decision.open_objections.includes(:owner).each do |objection|
            list << [t("objection", name: objection.owner&.name || "–", quote: objection.quote.truncate(60)), objection]
          end
          supporters = Assistant::Intent.where(project:, subject: decision.subject).where.not(owner_id: [decision.owner_id, nil])
                                         .where(stated_at: (decision.stated_at - 3.days)..(decision.stated_at + 3.days)).count
          thin_data = !decision.quote.match?(DATA_HINT)
          list << [t("alone"), nil] if supporters.zero? && thin_data
          list
        end

        def options(decision, reasons)
          wp = decision.subject.is_a?(WorkPackage) ? decision.subject : nil
          return [] unless wp

          list = []
          objection = reasons.filter_map(&:last).first
          if objection&.owner
            list << option(t("answer", name: objection.owner.name), t("answer_consequence"), "answer_objection",
                           [comment(wp, t("answer_comment", who: mention(objection.owner), quote: objection.quote.truncate(80)))])
          end
          list << option(t("validate"), t("validate_consequence"), "plan_validation",
                         [{ "op" => "create_work_package",
                            "attributes" => { "project_id" => project.id, "parent_id" => wp.parent_id || wp.id,
                                              "subject" => t("validate_subject", title: decision.title.truncate(60)),
                                              "description" => t("validate_description", quote: decision.quote, ref: "##{wp.id}"),
                                              "estimated_hours" => 4 } }])
          list
        end
      end
    end
  end
end
