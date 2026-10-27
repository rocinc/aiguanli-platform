# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkPackageRole do
  let(:work_package_role) { build(:view_work_package_role) }

  subject do
    described_class.create(name: "work_package_role",
                           permissions: %w[permissions])
  end

  describe "#member?" do
    it "is one (even though it is builtin)" do
      expect(work_package_role).to be_member
    end
  end
end
