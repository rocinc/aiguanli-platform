# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe TwoFactorAuthentication::LoginToken, :with_2fa_ee do
  shared_let(:user) { create(:user) }
  let!(:token) { described_class.new user: }

  it "expires after 15 minutes" do
    Timecop.travel(16.minutes.from_now) do
      expect(token).to be_expired
    end
  end

  it "does not expire before 15 minutes" do
    Timecop.travel(14.minutes.from_now) do
      expect(token).not_to be_expired
    end
  end

  it "deletes previous tokens for the user on creation" do
    token.save!

    new_token = described_class.new(user:)
    new_token.save!

    expect(described_class.find_by(id: token.id)).to be_nil
    expect(described_class.find(new_token.id)).not_to be_nil
  end

  describe ".generate_token_value" do
    subject { described_class.generate_token_value }

    it "generates tokens consisting of 6 numerical digits" do
      expect(subject).to match(/\A[0-9]{6}\z/)
    end

    it "generates tokens that can contain any digit (regression test)" do
      generated_digits = ""
      100.times { generated_digits += described_class.generate_token_value }

      (0..9).each do |digit|
        expect(generated_digits).to include(digit.to_s)
      end
    end
  end
end
