# frozen_string_literal: true

require "spec_helper"

RSpec.describe DesignColor do
  let(:default_primary) { OpenProject::CustomStyles::Design.variables["primary-button-color"] }
  let(:primary_color) { create(:"design_color_primary-button-color") }

  describe "normalization" do
    it "does not normalize non-hexcodes, except to strip whitespace", :aggregate_failures do
      expect(subject).to normalize(:hexcode).from("").to("")
      expect(subject).to normalize(:hexcode).from(" ").to("")
      expect(subject).to normalize(:hexcode).from("11").to("11")
      expect(subject).to normalize(:hexcode).from("purple").to("purple")
      expect(subject).to normalize(:hexcode).from("green ").to("green")
    end

    it "normalizes short hexcodes", :aggregate_failures do
      expect(subject).to normalize(:hexcode).from(" ccc").to("#CCCCCC")
      expect(subject).to normalize(:hexcode).from("333 ").to("#333333")
      expect(subject).to normalize(:hexcode).from("#ddd").to("#DDDDDD")
    end

    it "normalizes full hexcodes", :aggregate_failures do
      expect(subject).to normalize(:hexcode).from(" 800080").to("#800080")
      expect(subject).to normalize(:hexcode).from("228b22 ").to("#228B22")
      expect(subject).to normalize(:hexcode).from("#00CED1").to("#00CED1")
    end
  end

  describe "#setables" do
    it "returns an Array of instances" do
      expect(described_class.setables).to be_a(Array)
      expect(described_class.setables.first).to be_a(described_class)
    end

    it "not overwritten defaults do not have a color set" do
      expect(described_class.setables.first.hexcode).to be_nil
    end

    it "instances overwrite defaults" do
      primary_color
      expect(described_class.setables.first.hexcode).to eq("#3493B3")
      expect(described_class.setables.second.hexcode).to be_nil
    end
  end

  describe "validations" do
    it "validates variable is present and unique" do
      expect(subject).to validate_presence_of(:variable)
      expect(subject).to validate_uniqueness_of(:variable)
    end

    it "validates hexcode is present" do
      expect(subject).to validate_presence_of(:hexcode)
    end

    it "does not allow malformed hexcodes" do
      expect(subject).not_to allow_values(
        "1",
        "#1",
        "#1111111",
        "#HHHHHH"
      )
      .for(:hexcode)
      .with_message("is not a valid 6-digit hexadecimal color code.")
    end

    it "allows valid hexcodes" do
      expect(subject).to allow_values(
        "111111",
        "#111111",
        "#ABC123",
        "#111",
        "111"
      ).for(:hexcode)
    end
  end

  describe "#hexcode" do
    it "returns hexcode if present" do
      primary_color
      expect(primary_color.hexcode).to eq("#3493B3")
    end

    it "returns nil hexcode if hexcode not present" do
      expect(described_class.new(variable: "primary-button-color").hexcode)
        .to be_nil
    end
  end

  describe "#create" do
    context "no CustomStyle.current exists yet" do
      subject { described_class.new variable: "foo", hexcode: "#111111" }

      it "creates a CustomStyle.current" do
        expect(CustomStyle.current).to be_nil
        subject.save
        expect(CustomStyle.current).to be_present
      end
    end
  end
end
