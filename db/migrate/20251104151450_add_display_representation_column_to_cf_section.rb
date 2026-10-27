# frozen_string_literal: true

class AddDisplayRepresentationColumnToCfSection < ActiveRecord::Migration[8.0]
  def change
    add_column :custom_field_sections,
               :display_representation,
               :jsonb,
               default: { overview: CustomFieldSection::DEFAULT_OVERVIEW_KEY },
               null: false
  end
end
