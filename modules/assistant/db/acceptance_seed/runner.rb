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

require_relative "context"
require_relative "work_package_rows"
require_relative "work_package_talk"
require_relative "reset"
require_relative "team"
require_relative "work"
require_relative "time_log"
require_relative "community"
require_relative "ledger"
require_relative "notebook"
require_relative "../demo_seed/steps"

module AssistantSeed
  class Runner
    def initialize(today:, dry_run: false)
      @ctx = Context.new(today)
      @dry_run = dry_run
    end

    def call
      raise "assistant:seed_acceptance rewrites demo data; run it in development" unless Rails.env.development? || ENV["ASSISTANT_SEED_FORCE"] == "1"

      @ctx.say("today=#{@ctx.today} monday=#{@ctx.monday}#{' (dry run)' if @dry_run}")
      quietly do
        committed = build
        Ledger.new(@ctx).last_logins if committed
      end
      report unless @dry_run
    end

    private

    def build
      ActiveRecord::Base.transaction do
        (([Reset, Team, Work, TimeLog, Community, Ledger, Notebook]) + demo_steps).each do |step|
          step.new(@ctx).call
          @ctx.say(step.name.demodulize)
        end
        sync_target_versions
        clear_noise
        add_marker
        demo_hook(:before_sweep)
        sweep
        demo_hook(:after_sweep)
        settle_timestamps
        raise ActiveRecord::Rollback if @dry_run
      end
      !@dry_run
    end

    def demo_steps = ENV["ASSISTANT_SEED_DEMO"] == "1" ? DemoSeed.steps : []

    def demo_hook(phase)
      DemoSeed::LedgerDemo.public_send(phase, @ctx) if defined?(DemoSeed::LedgerDemo)
    end

    def quietly(&)
      logger = Rails.logger.level
      adapter = ActiveJob::Base.queue_adapter
      minutes = Setting.journal_aggregation_time_minutes
      Rails.logger.level = :warn
      ActiveRecord::Base.logger = nil
      ActiveJob::Base.queue_adapter = :test
      Setting.journal_aggregation_time_minutes = 0
      without_immediate_asides(&)
    ensure
      Setting.journal_aggregation_time_minutes = minutes
      ActiveJob::Base.queue_adapter = adapter
      Rails.logger.level = logger
    end

    def without_immediate_asides
      singleton = Assistant::Proactive::Immediate.singleton_class
      singleton.alias_method :seeded_after_save, :after_save
      singleton.define_method(:after_save) { |*| nil }
      yield
    ensure
      singleton.alias_method :after_save, :seeded_after_save
      singleton.remove_method :seeded_after_save
    end

    def sync_target_versions
      rows = WorkPackage.where.not(version_id: nil)
                        .where.not(id: WorkPackageVersion.where(kind: "target").select(:work_package_id))
                        .pluck(:id, :version_id).map { |id, version_id| { work_package_id: id, version_id:, kind: "target" } }
      WorkPackageVersion.insert_all(rows) if rows.any?
    end

    def clear_noise
      [Assistant::Signal, Assistant::Action, Assistant::Message, Assistant::Conversation].each(&:delete_all)
    end

    def add_marker
      stamp = @ctx.at(-5, "00:00")
      [@ctx.project, Project.find_by!(identifier: Notebook::IDENTIFIER)].each do |project|
        Assistant::Event.create!(kind: "project.swept", subject: project, project:, actor: nil, changes_made: {},
                                 created_at: stamp, processed_at: stamp)
      end
    end

    def settle_timestamps
      [Assistant::Signal, Assistant::Action].each do |model|
        model.where(created_at: (@ctx.now + 1.second)..).update_all(created_at: @ctx.now, updated_at: @ctx.now)
      end
    end

    def with_clock(&)
      return yield unless ENV["ASSISTANT_SEED_CLOCK"] == "1" && defined?(Timecop)

      Timecop.travel(@ctx.now, &)
    end

    def sweep
      with_clock { sweep_projects }
    end

    def sweep_projects
      User.current = @ctx.admin
      [@ctx.project, Project.find_by!(identifier: Notebook::IDENTIFIER)].each do |project|
        signals = Assistant::Proactive::Engine.new(project, today: @ctx.today, now: @ctx.now).sweep
        @ctx.say("sweep #{project.identifier}: #{signals.compact.size} signals")
      end
    end

    def report
      counts = {
        work_packages: WorkPackage.where(project: @ctx.project).count, time_entries: TimeEntry.where(project_id: @ctx.project.id).count,
        meetings: Meeting.where(project: @ctx.project).count, relations: Relation.count,
        intents: Assistant::Intent.count, signals: Assistant::Signal.count, actions: Assistant::Action.count,
        journals: Journal.where(journable_type: "WorkPackage", journable_id: WorkPackage.where(project: @ctx.project).select(:id)).count
      }
      @ctx.say(counts.map { "#{_1}=#{_2}" }.join(" "))
    end
  end
end
