# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

RSpec.describe Assistant::Actions::Steps do
  describe ".sentence_of" do
    it "gives a sentence even when the platform has no words for the attribute" do
      error = instance_double(ActiveModel::Error)
      allow(error).to receive(:full_message).and_raise(I18n::MissingTranslationData.new(:en, "attributes.requested_by"))

      expect(described_class.sentence_of(error)).to eq(I18n.t("assistant.actions.errors.refused"))
    end

    it "keeps the platform's own sentence otherwise" do
      wp = WorkPackage.new.tap(&:valid?)

      expect(described_class.sentences(wp.errors)).to include("Type can't be blank.")
    end
  end
end
