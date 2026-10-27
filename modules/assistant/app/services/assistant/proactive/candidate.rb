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
    # Something a detector noticed, before anyone decided it is worth saying.
    #
    # recipient       who it is for (routing may add people later)
    # subject         the object it is about (a work package, version, sprint…)
    # fingerprint     the same thing noticed again has the same fingerprint
    # facts           computed facts, passed to the writer and shown as basis
    # because         one line per fact, shown under "basis"
    # nature          :own (someone's own slip), :object, :team, :decision, :opportunity, :intro (the assistant introducing itself)
    # certainty       :fact (computed) or :likely (from a reading of words)
    # impact          { critical_path:, external:, people:, money:, cascade: }
    # act_by          by when acting still changes the outcome
    # effort_days     working days the recipient needs to act
    # steps_for       builds the options: ->(recipient) { [{ label:, kind:, steps: }] }
    # waiting         who is waiting on the recipient (for the escalation ladder)
    # channel         preferred channel when allowed: "inline", "brief", "notification", "comment"
    Candidate = Data.define(:detector, :fingerprint, :recipient, :subject, :project, :facts, :because, :nature,
                            :certainty, :impact, :act_by, :effort_days, :steps_for, :waiting, :channel, :headline) do
      def self.build(**attributes)
        defaults = { facts: {}, because: [], nature: :object, certainty: :fact, impact: {}, act_by: nil, effort_days: 0,
                     steps_for: nil, waiting: nil, channel: nil, headline: nil, project: attributes[:subject].try(:project) }
        new(**defaults, **attributes)
      end

      def options_for(user) = steps_for ? Array(steps_for.call(user)) : []

      def key = [detector, fingerprint, recipient.id]
    end
  end
end
