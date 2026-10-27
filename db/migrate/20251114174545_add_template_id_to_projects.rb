# frozen_string_literal: true

class AddTemplateIdToProjects < ActiveRecord::Migration[8.0]
  def change
    add_reference :projects, :template, foreign_key: { to_table: :projects }
  end
end
