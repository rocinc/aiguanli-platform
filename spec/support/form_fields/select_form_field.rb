# frozen_string_literal: true

require_relative "form_field"

module FormFields
  class SelectFormField < FormField
    def expect_selected(*values)
      values.each do |val|
        expect(field_container).to have_css(".ng-value", text: val)
      end
    end

    def expect_no_option(option)
      field_container.find(".ng-select-container").click

      expect(page)
        .to have_no_css(".ng-option", text: option, visible: :all)
    end

    def expect_option(option, grouping: nil)
      field_container.find(".ng-select-container").click
      if grouping
        # Make sure the option is displayed under correct grouping title.
        option_group = find(".ng-optgroup", text: grouping)
        option = find(".ng-option.ng-option-child", text: option, visible: :visible)

        expected_group = begin
          option.find(:xpath,
                      "preceding-sibling::*[contains(@class, 'ng-optgroup')][1]",
                      wait: false)
        rescue Capybara::ElementNotFound
          raise "Unable to find the '.ng-optgroup' grouping for option '#{option.text}'"
        end

        expect(option_group).to eq(expected_group), <<~MSG
          Expected the option '#{option.text}' to be under the group '#{option_group.text}',
          but it was under '#{expected_group.text}' instead.
        MSG
      else
        expect(page)
          .to have_css(".ng-option", text: option, visible: :visible)
      end
    end

    def expect_visible
      expect(field_container).to have_css("ng-select")
    end

    def select_option(*values)
      values.each do |val|
        field_container.find(".ng-select-container").click
        page.find(".ng-option", text: val, visible: :all).click
        sleep 1
      end
    end

    def search(text)
      field_container.find(".ng-select-container input").set text
    end
  end
end
