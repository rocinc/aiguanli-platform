# frozen_string_literal: true

class AddCaptionToAttributeHelpTexts < ActiveRecord::Migration[8.0]
  def change
    add_column :attribute_help_texts, :caption, :text
  end
end
