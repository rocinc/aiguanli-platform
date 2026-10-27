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

require "open_project/plugins"
require "open_project/assistant/mail_guard"

module OpenProject::Assistant
  class Engine < ::Rails::Engine
    engine_name :openproject_assistant

    include OpenProject::Plugins::ActsAsOpEngine

    register "openproject-assistant",
             author_url: "https://www.openproject.org",
             bundled: true do
      project_module :assistant do
        permission :use_assistant,
                   {
                     "assistant/actions": %i[show approve reject undo handover],
                     "assistant/signals": %i[update],
                     "assistant/conversations": %i[create reply panel],
                     "assistant/performance": %i[show note],
                     "assistant/desk": %i[show pause resume],
                     "assistant/ideas": %i[convert merge release restore]
                   },
                   permissible_on: :project,
                   require: :member,
                   dependencies: :view_work_packages
        permission :manage_assistant,
                   {
                     "assistant/duties": %i[create update destroy],
                     "assistant/grants": %i[create destroy],
                     "projects/settings/assistant": %i[show update]
                   },
                   permissible_on: :project,
                   require: :member,
                   dependencies: :use_assistant
        permission :view_member_performance,
                   { "assistant/performance": %i[team] },
                   permissible_on: :project,
                   require: :member,
                   dependencies: :use_assistant
        permission :appraise_members,
                   { "assistant/performance": %i[draft finalize] },
                   permissible_on: :project,
                   require: :member,
                   dependencies: :view_member_performance
      end

      menu :project_menu,
           :assistant,
           { controller: "/assistant/desk", action: "show" },
           caption: :label_assistant,
           after: :meetings,
           icon: "sparkle-fill"

      menu :project_menu,
           :settings_assistant,
           { controller: "/projects/settings/assistant", action: :show },
           if: ->(project) { project.module_enabled?(:assistant) },
           caption: :label_assistant_project_settings,
           parent: :settings,
           before: :settings_storage

      having_assistant = ->(_) { User.current.logged? && ::Assistant::PanelDialogComponent.anywhere?(User.current) }

      menu :account_menu,
           :assistant_settings,
           { controller: "/assistant/my_settings", action: :show },
           if: having_assistant,
           caption: :label_assistant_my_settings,
           icon: "sparkle-fill",
           after: :my_account

      menu :account_menu,
           :assistant_performance,
           { controller: "/assistant/my_performance", action: :show },
           if: having_assistant,
           caption: :label_assistant_my_performance,
           icon: "graph",
           after: :assistant_settings

      menu :my_menu,
           :assistant_settings,
           { controller: "/assistant/my_settings", action: :show },
           if: having_assistant,
           caption: :label_assistant_my_settings,
           icon: "sparkle-fill"

      menu :my_menu,
           :assistant_performance,
           { controller: "/assistant/my_performance", action: :show },
           if: having_assistant,
           caption: :label_assistant_my_performance,
           icon: "graph",
           after: :assistant_settings

      menu :admin_menu,
           :assistant_settings,
           { controller: "/assistant/admin/settings", action: :show },
           if: ->(_) { User.current.admin? },
           caption: :label_assistant_settings,
           icon: "sparkle-fill"
    end

    extend_api_response(:v3, :work_packages, :work_package) do
      link :assistantNotice, uncacheable: true do
        headline = ::Assistant::ListMarks.headline(represented, current_user)
        next if headline.blank?

        { href: ::Rails.application.routes.url_helpers.assistant_work_package_line_path(represented.id), title: headline }
      end
    end

    config.action_cable.connection_class = -> { ::Assistant::Cable::Connection }

    initializer "assistant.mail_guard" do
      ActionMailer::Base.register_interceptor(OpenProject::Assistant::MailGuard)
    end

    initializer "assistant.settings" do
      ::Settings::Definition.add :assistant_display_name, format: :string, default: nil
      ::Settings::Definition.add :assistant_reasoning_model, format: :string, default: nil
      ::Settings::Definition.add :assistant_monthly_token_budget, format: :integer, default: 20_000_000
      ::Settings::Definition.add :assistant_default_proactivity, format: :string, default: "standard"
      # 04 D5: reading the content of documents and attachments is a separate consent.
      ::Settings::Definition.add :assistant_read_attachments, format: :boolean, default: false
      # The administrator agrees that what people write is sent to this endpoint.
      ::Settings::Definition.add :assistant_llm_consent, format: :boolean, default: false
      ::Settings::Definition.add :assistant_llm_base_url, format: :string, default: nil
      ::Settings::Definition.add :assistant_llm_name, format: :string, default: nil
    end

    replace_principal_references "Assistant::Action" => %i[on_behalf_of_id decided_by_id undone_by_id],
                                 "Assistant::Duty" => %i[delegator_id],
                                 "Assistant::Grant" => %i[granted_by_id],
                                 "Assistant::Appraisal" => %i[author_id]

    add_cron_jobs do
      {
        "Assistant::ProactiveSweepJob": { cron: "*/10 * * * *", class: ::Assistant::ProactiveSweepJob.name },
        "Assistant::DeliverJob": { cron: "* * * * *", class: ::Assistant::DeliverJob.name },
        "Assistant::BriefMailJob": { cron: "*/15 * * * *", class: ::Assistant::BriefMailJob.name },
        "Assistant::DutiesJob": { cron: "*/15 * * * *", class: ::Assistant::DutiesJob.name },
        "Assistant::FollowUpJob": { cron: "7 * * * *", class: ::Assistant::FollowUpJob.name }
      }
    end

    config.after_initialize do
      ::Assistant::Events::Recorder.subscribe!
      ::Assistant::Proactive::Immediate.subscribe!
      ::Assistant::Events::Dispatch.subscribe!
      ::Assistant::Understanding::Capture.subscribe!
      ::Assistant::Understanding::MeetingCapture.subscribe!

      ::OpenProject::Notifications.subscribe(::OpenProject::Events::MODULE_ENABLED) do |payload|
        enabled = payload[:enabled_module]
        if enabled&.name == "assistant" && enabled.project
          ::Assistant::Membership.ensure_member!(enabled.project)
          ::Assistant::Duties::Defaults.enabler&.then { ::Assistant::Duties::Defaults.ensure!(enabled.project, it) }
        end
      end
    end

    config.to_prepare do
      ::OpenProject::JournalFormatter::Cause.prepend(::Assistant::Provenance::CauseRendering)
      ::WorkPackage.prepend(::Assistant::WatchablePatch) unless ::WorkPackage <= ::Assistant::WatchablePatch
      ::WorkPackage.prepend(::Assistant::VersionMovePatch) unless ::WorkPackage <= ::Assistant::VersionMovePatch
      ::Assistant::MeetingPatch.install!
      ::Assistant::ChangeRecording.install!
      ::Notifications::Menu.register_reason(:assistant, icon: :"sparkle-fill")
      OpenProject::Assistant::Hooks

      # 04 F3: the fact and action tools for outside agents, under the same tiers.
      ::McpTools.register(*::McpTools::AssistantTool.all.reject { ::McpTools.all.include?(it) })

      unless ::Grids::Configuration.all_widget_identifiers(::Grids::MyPage).include?("assistant_today")
        ::Grids::Configuration.register_widget("assistant_today", "Grids::MyPage")
      end
      ::MyPage::GridRegistration.widget_strategy("assistant_today") do
        allowed ->(user, _project) { ::Assistant::PanelDialogComponent.anywhere?(user) }
      end
      ::Assistant::MyPageDefaults.apply!
    end
  end
end
