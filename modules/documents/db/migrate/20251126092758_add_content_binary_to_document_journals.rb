# frozen_string_literal: true

class AddContentBinaryToDocumentJournals < ActiveRecord::Migration[8.0]
  def change
    add_column :document_journals, :content_binary, :text
  end
end
