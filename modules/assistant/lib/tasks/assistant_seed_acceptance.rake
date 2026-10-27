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

# Usage: [ASSISTANT_SEED_TODAY=2026-10-12] [ASSISTANT_SEED_CLOCK=1] [DRY_RUN=1] bin/rails assistant:seed_acceptance
namespace :assistant do
  desc "Rebuild the quill demo project and its assistant ledger for acceptance (dev only; CLOCK=1 sweeps on the seeded date)"
  task seed_acceptance: :environment do
    require_relative "../../db/acceptance_seed/runner"

    today = ENV["ASSISTANT_SEED_TODAY"].presence ? Date.iso8601(ENV.fetch("ASSISTANT_SEED_TODAY", nil)) : Date.current
    AssistantSeed::Runner.new(today:, dry_run: ENV["DRY_RUN"] == "1").call
  end
end
