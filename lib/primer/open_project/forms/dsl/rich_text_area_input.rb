# frozen_string_literal: true

module Primer
  module OpenProject
    module Forms
      module Dsl
        class RichTextAreaInput < Primer::Forms::Dsl::Input
          attr_reader :name, :label, :classes, :wrapper_data_attributes, :wrapper_classes

          def initialize(name:, label:, rich_text_options:, wrapper_data_attributes: {}, wrapper_classes: nil, **system_arguments)
            @name = name
            @label = label
            @rich_text_options = rich_text_options
            @wrapper_data_attributes = wrapper_data_attributes
            @wrapper_classes = wrapper_classes
            @classes = system_arguments[:classes]

            super(**system_arguments)
          end

          def to_component
            RichTextArea.new(input: self, rich_text_options: @rich_text_options,
                             wrapper_data_attributes: @wrapper_data_attributes, wrapper_classes: @wrapper_classes)
          end

          def type
            :rich_text_area
          end

          def focusable?
            true
          end
        end
      end
    end
  end
end
