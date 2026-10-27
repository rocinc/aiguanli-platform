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

Rails.application.routes.draw do
  scope "assistant", as: "assistant" do
    resources :actions, only: %i[show], controller: "assistant/actions" do
      member do
        post :approve
        post :reject
        post :undo
        post :revise
        post :handover
      end
    end
    resources :signals, only: %i[update], controller: "assistant/signals"
    resources :conversations, only: %i[create], controller: "assistant/conversations" do
      member do
        post :reply
        get :sync
      end
    end
    get "panel", to: "assistant/conversations#panel", as: :panel
    get "avatar", to: "assistant/avatars#show", as: :avatar, defaults: { format: :svg }
    get "conversations/:id/messages/:message_id", to: "assistant/conversations#message", as: :conversation_message
    post "conversations/:id/messages/:message_id/stop", to: "assistant/conversations#stop", as: :stop_conversation_message
    get "references", to: "assistant/references#index", as: :references
    get "work_packages/:work_package_id/aside", to: "assistant/asides#show", as: :work_package_aside
    get "work_packages/:work_package_id/field_aside", to: "assistant/asides#field", as: :work_package_field_aside
    get "versions/:version_id/date_aside", to: "assistant/version_asides#show", as: :version_date_aside
    get "work_packages/duplicate_aside", to: "assistant/asides#duplicate", as: :duplicate_aside
    get "work_packages/:work_package_id/line", to: "assistant/object_lines#show", as: :work_package_line
    get "agenda_items/:agenda_item_id/proposals", to: "assistant/source_signals#show", as: :agenda_item_proposals
    get "journals/:journal_id/reading", to: "assistant/readings#show", as: :journal_reading
    get "today", to: "assistant/briefs#widget", as: :today_widget
    get "notifications/:id", to: "assistant/notifications#show", as: :notification
    post "views", to: "assistant/views#create", as: :views
    resources :writings, only: %i[index create show], controller: "assistant/writings" do
      member { post :cancel }
    end
  end

  scope "projects/:project_id", as: "project" do
    get "assistant", to: "assistant/desk#show", as: :assistant_desk
    post "assistant/pause", to: "assistant/desk#pause", as: :assistant_pause
    delete "assistant/pause", to: "assistant/desk#resume"
    resources :assistant_duties, only: %i[create update destroy], controller: "assistant/duties",
                                 path: "assistant/duties"
    resources :assistant_grants, only: %i[create destroy], controller: "assistant/grants", path: "assistant/grants"
    resources :assistant_ideas, only: [], controller: "assistant/ideas", path: "assistant/ideas" do
      member do
        post :convert
        post :merge
        post :release
        post :restore
      end
    end
    get "members/performance", to: "assistant/performance#team", as: :performance_team
    get "members/:user_id/performance", to: "assistant/performance#show", as: :member_performance
    post "members/:user_id/performance/draft", to: "assistant/performance#draft", as: :draft_member_performance
    post "members/:user_id/performance/finalize", to: "assistant/performance#finalize", as: :finalize_member_performance
    post "members/:user_id/performance/notes", to: "assistant/performance#note", as: :member_performance_notes
  end

  get "my/performance", to: "assistant/my_performance#show", as: :my_performance

  resource :my_assistant, path: "my/assistant", controller: "assistant/my_settings", only: %i[show update] do
    delete "mutes", action: :unmute, as: :mute
    delete "grants/:id", action: :revoke, as: :grant
  end

  scope "projects/:project_id", as: "project", module: "projects" do
    namespace "settings" do
      resource :assistant, only: %i[show update], controller: "assistant"
    end
  end

  scope "admin/settings", as: "admin_settings" do
    resource :assistant, controller: "assistant/admin/settings", only: %i[show update] do
      post :test_connection
    end
  end
end

Rails.application.routes.draw do
  scope "assistant", as: "assistant" do
    get "intents/:intent_id/verbs/:verb", to: "assistant/intent_verbs#show", as: :intent_verb
    post "intents/:intent_id/verbs/:verb", to: "assistant/intent_verbs#act"
    post "intents/:intent_id/verbs/:verb/preview", to: "assistant/intent_verbs#preview", as: :preview_intent_verb
    post "intents/:intent_id/unshelve", to: "assistant/intent_verbs#undo", as: :shelved_intent
  end
end
