# frozen_string_literal: true

module Primer
  module OpenProject
    module Forms
      # :nodoc:
      class RichTextArea < Primer::Forms::BaseComponent
        include AngularHelper

        delegate :builder, :form, to: :@input

        def initialize(input:, rich_text_options:, wrapper_data_attributes: {}, wrapper_classes: nil)
          super()
          @input = input
          @wrapper_data_attributes = wrapper_data_attributes
          @wrapper_classes = wrapper_classes
          @rich_text_data = rich_text_options.delete(:data) { {} }
          @rich_text_data[:"test-selector"] ||= "augmented-text-area-#{@input.name}"
          @rich_text_options = rich_text_options
          @text_area_id =
            if @input.id
              [builder.options[:namespace], @input.id].compact.join("_")
            else
              builder.field_id(@input.name)
            end
        end
      end
    end
  end
end
