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

# The understanding layer used to live in its own module with its own tables.
# On a database that has them, the rows move over; on a fresh one, the tables
# are created. Events and links are dropped: what they carried is now three
# columns on the intent (who answered it, which work package it became, which
# decision an objection is raised against).
class MergeCoordinationIntoAssistant < ActiveRecord::Migration[8.1]
  SETTINGS = {
    "coordination_language_model_consent" => "assistant_llm_consent",
    "coordination_language_model_base_url" => "assistant_llm_base_url",
    "coordination_language_model_name" => "assistant_llm_name"
  }.freeze

  def up
    table_exists?(:coordination_items) ? move_tables : create_tables
    drop_table :assistant_reflection_entries, if_exists: true
    drop_table :assistant_reflections, if_exists: true
    move_settings
    move_project_modules
    drop_permission_and_notifications
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def create_tables
    create_table :assistant_intents do |t|
      t.references :project, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :status, null: false
      t.string :strength, null: false, default: "firm"
      t.string :title, null: false
      t.text :quote, null: false
      t.references :owner, foreign_key: { to_table: :users }
      t.references :counterparty, foreign_key: { to_table: :users }
      t.references :source, polymorphic: true, null: false
      t.references :subject, polymorphic: true, null: false
      t.string :said_due_expression
      t.date :said_due_on
      t.references :due_anchor, polymorphic: true
      t.boolean :internal, null: false, default: false
      t.boolean :external_exposure, null: false, default: false
      t.references :supersedes, foreign_key: { to_table: :assistant_intents }
      t.references :parent, foreign_key: { to_table: :assistant_intents }
      t.references :answered_by, polymorphic: true
      t.references :work_package, foreign_key: { on_delete: :nullify }
      t.integer :moves, null: false, default: 0
      t.datetime :stated_at, null: false
      t.datetime :resolved_at
      t.string :extractor_version, null: false
      t.timestamps
    end
    add_index :assistant_intents, %i[project_id kind status]
    add_index :assistant_intents, %i[owner_id status said_due_on]
    add_index :assistant_intents, %i[counterparty_id status]
    add_index :assistant_intents, :title, using: :gin, opclass: :gin_trgm_ops

    create_extractions
  end

  def create_extractions
    create_table :assistant_extractions do |t|
      t.references :project, null: false, foreign_key: true
      t.references :source, polymorphic: true, null: false
      t.string :extractor_version, null: false
      t.string :source_digest, null: false
      t.string :status, null: false
      t.integer :items_count, null: false, default: 0
      t.text :error
      t.timestamps
    end
    add_index :assistant_extractions, %i[source_type source_id extractor_version], unique: true,
                                                                                   name: "index_assistant_extractions_once"
  end

  def move_tables
    rename_table :coordination_items, :assistant_intents
    rename_table :coordination_extractions, :assistant_extractions
    remove_index :assistant_extractions, name: "index_coordination_extractions_once"
    remove_column :assistant_extractions, :tokens
    add_index :assistant_extractions, %i[source_type source_id extractor_version], unique: true,
                                                                                   name: "index_assistant_extractions_once"

    %w[due_anchor source subject].each do |name|
      rename_index :assistant_intents, "index_coordination_items_on_#{name}", "index_assistant_intents_on_#{name}"
    end
    rename_index :assistant_extractions, "index_coordination_extractions_on_source", "index_assistant_extractions_on_source"

    change_table :assistant_intents do |t|
      t.rename :due_on, :said_due_on
      t.rename :due_expression, :said_due_expression
      t.references :parent, foreign_key: { to_table: :assistant_intents }
      t.references :answered_by, polymorphic: true
      t.references :work_package, foreign_key: { on_delete: :nullify }
      t.integer :moves, null: false, default: 0
    end
    remove_columns :assistant_intents, :confirmed_at, :last_nudged_at, :nudge_count

    execute <<~SQL.squish
      UPDATE assistant_intents i SET answered_by_type = l.linked_type, answered_by_id = l.linked_id
      FROM coordination_links l WHERE l.item_id = i.id AND l.relation = 'answers' AND l.linked_type = 'Journal'
    SQL
    execute <<~SQL.squish
      UPDATE assistant_intents i SET work_package_id = l.linked_id
      FROM coordination_links l JOIN work_packages w ON w.id = l.linked_id
      WHERE l.item_id = i.id AND l.relation = 'created_work_package' AND l.linked_type = 'WorkPackage'
    SQL
    execute <<~SQL.squish
      UPDATE assistant_intents i SET parent_id = l.linked_id
      FROM coordination_links l JOIN assistant_intents d ON d.id = l.linked_id
      WHERE l.item_id = i.id AND l.relation = 'objection' AND l.linked_type = 'Coordination::Item'
    SQL

    execute <<~SQL.squish
      UPDATE assistant_intents i SET moves = c.n
      FROM (SELECT item_id, COUNT(*) AS n FROM coordination_events WHERE kind = 'renegotiated' GROUP BY item_id) c
      WHERE c.item_id = i.id
    SQL

    drop_table :coordination_links
    drop_table :coordination_events
  end

  def move_settings
    SETTINGS.each do |from, to|
      execute "UPDATE settings SET name = #{quote(to)} WHERE name = #{quote(from)} " \
              "AND NOT EXISTS (SELECT 1 FROM settings WHERE name = #{quote(to)})"
      execute "DELETE FROM settings WHERE name = #{quote(from)}"
    end
  end

  def move_project_modules
    execute <<~SQL.squish
      UPDATE enabled_modules SET name = 'assistant'
      WHERE name = 'coordination'
        AND NOT EXISTS (SELECT 1 FROM enabled_modules a WHERE a.name = 'assistant' AND a.project_id = enabled_modules.project_id)
    SQL
    execute "DELETE FROM enabled_modules WHERE name = 'coordination'"
  end

  def drop_permission_and_notifications
    execute "DELETE FROM role_permissions WHERE permission = 'view_coordination'" if table_exists?(:role_permissions)
    execute "DELETE FROM notifications WHERE reason = 14"
  end
end
