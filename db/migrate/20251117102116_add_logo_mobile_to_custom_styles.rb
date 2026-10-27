# frozen_string_literal: true

class AddLogoMobileToCustomStyles < ActiveRecord::Migration[8.0]
  def change
    add_column :custom_styles, :logo_mobile, :string
  end
end
