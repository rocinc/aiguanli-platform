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

class CreateAssistantTables < ActiveRecord::Migration[8.1]
  def change
    create_table :assistant_events do |t|
      t.string :kind, null: false
      t.references :subject, polymorphic: true, null: false, index: false
      t.references :project, foreign_key: { on_delete: :cascade }, index: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :journal, foreign_key: { on_delete: :nullify }, index: false
      t.jsonb :changes_made, null: false, default: {}
      t.datetime :processed_at
      t.datetime :created_at, null: false
    end
    add_index :assistant_events, %i[subject_type subject_id created_at]
    add_index :assistant_events, %i[project_id created_at]
    add_index :assistant_events, :created_at, where: "processed_at IS NULL", name: "index_assistant_events_unprocessed"

    create_table :assistant_actions do |t|
      t.string :kind, null: false
      t.string :status, null: false, default: "proposed"
      t.string :tier, null: false
      t.references :project, foreign_key: { on_delete: :cascade }
      t.references :on_behalf_of, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :subject, polymorphic: true
      t.string :title, null: false
      t.jsonb :basis, null: false, default: []
      t.jsonb :plan, null: false, default: {}
      t.jsonb :preview, null: false, default: {}
      t.jsonb :inverse, null: false, default: []
      t.jsonb :journal_ids, null: false, default: []
      t.text :error
      t.references :decided_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :executed_at
      t.datetime :undone_at
      t.references :undone_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :assistant_actions, %i[project_id status created_at]

    create_table :assistant_signals do |t|
      t.string :detector, null: false
      t.string :fingerprint, null: false
      t.references :project, foreign_key: { on_delete: :cascade }
      t.references :recipient, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :subject, polymorphic: true
      t.references :action, foreign_key: { to_table: :assistant_actions, on_delete: :nullify }
      t.integer :stage, null: false, default: 0
      t.string :channel, null: false
      t.string :state, null: false, default: "pending"
      t.integer :score, null: false, default: 0
      t.jsonb :payload, null: false, default: {}
      t.datetime :deliver_at, null: false
      t.datetime :delivered_at
      t.datetime :seen_at
      t.string :outcome
      t.datetime :outcome_at
      t.datetime :snoozed_until
      t.timestamps
    end
    add_index :assistant_signals, %i[recipient_id detector fingerprint], unique: true,
                                                                         name: "index_assistant_signals_once"
    add_index :assistant_signals, %i[recipient_id state deliver_at]
    add_index :assistant_signals, %i[detector outcome]

    create_table :assistant_duties do |t|
      t.string :kind, null: false
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :delegator, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.jsonb :scope, null: false, default: {}
      t.string :schedule
      t.boolean :active, null: false, default: true
      t.datetime :last_run_at
      t.jsonb :last_result, null: false, default: {}
      t.integer :unseen_runs, null: false, default: 0
      t.timestamps
    end
    add_index :assistant_duties, %i[project_id kind], unique: true

    create_table :assistant_grants do |t|
      t.string :action_kind, null: false
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.references :granted_by, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.jsonb :scope, null: false, default: {}
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :assistant_grants, %i[project_id action_kind], where: "revoked_at IS NULL",
                                                             name: "index_assistant_grants_live"

    create_table :assistant_preferences do |t|
      t.references :owner, polymorphic: true, null: false, index: { unique: true }
      t.string :proactivity
      t.integer :interrupt_cap
      t.jsonb :muted_detectors, null: false, default: []
      t.jsonb :thresholds, null: false, default: {}
      t.timestamps
    end

    create_table :assistant_ideas do |t|
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.string :title, null: false
      t.string :state, null: false, default: "open"
      t.references :work_package, foreign_key: { on_delete: :nullify }
      t.timestamps
    end

    create_table :assistant_idea_mentions do |t|
      t.references :idea, null: false, foreign_key: { to_table: :assistant_ideas, on_delete: :cascade }
      t.references :speaker, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :source, polymorphic: true, null: false
      t.text :quote, null: false
      t.datetime :said_at, null: false
      t.timestamps
    end

    create_table :assistant_conversations do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :project, foreign_key: { on_delete: :cascade }
      t.references :context, polymorphic: true
      t.string :title
      t.string :origin, null: false, default: "panel"
      t.timestamps
    end
    add_index :assistant_conversations, %i[user_id updated_at]

    create_table :assistant_messages do |t|
      t.references :conversation, null: false, foreign_key: { to_table: :assistant_conversations, on_delete: :cascade }
      t.string :role, null: false
      t.text :content
      t.jsonb :tool_calls, null: false, default: []
      t.string :tool_call_id
      t.jsonb :cards, null: false, default: []
      t.string :status, null: false, default: "done"
      t.timestamps
    end

    create_table :assistant_usages do |t|
      t.references :project, foreign_key: { on_delete: :nullify }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :purpose, null: false
      t.string :model
      t.integer :prompt_tokens, null: false, default: 0
      t.integer :completion_tokens, null: false, default: 0
      t.integer :duration_ms, null: false, default: 0
      t.integer :tool_calls, null: false, default: 0
      t.boolean :succeeded, null: false, default: true
      t.datetime :created_at, null: false
    end
    add_index :assistant_usages, %i[project_id created_at]
    add_index :assistant_usages, %i[user_id created_at]

    create_table :assistant_appraisals do |t|
      t.references :subject, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.date :period_start, null: false
      t.date :period_end, null: false
      t.jsonb :metrics, null: false, default: {}
      t.text :narrative
      t.references :author, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :finalized_at
      t.timestamps
    end
    add_index :assistant_appraisals, %i[project_id subject_id period_end]

    create_table :assistant_appraisal_notes do |t|
      t.references :subject, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.string :metric_key, null: false
      t.text :note, null: false
      t.timestamps
    end

    create_table :assistant_appraisal_views do |t|
      t.references :viewer, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :subject, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :created_at, null: false
    end
    add_index :assistant_appraisal_views, %i[subject_id created_at]
  end
end
