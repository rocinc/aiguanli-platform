# frozen_string_literal: true

class AddAutologinSessionLink < ActiveRecord::Migration[8.0]
  def change
    create_table :autologin_session_links do |t|
      t.belongs_to :token, null: false, index: true, foreign_key: { on_delete: :cascade }
      t.belongs_to :session, index: true, null: false # cascade deletion not possible for unlogged sessions table

      t.timestamps
    end
  end
end
