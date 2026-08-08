# frozen_string_literal: true

require "rails_helper"

describe ItineraryCalendarToken do
  fab!(:user)

  it "creates one stable token per user" do
    first = described_class.create_for_user!(user)
    second = described_class.create_for_user!(user)

    expect(second).to eq(first)
    expect(described_class.where(user_id: user.id).count).to eq(1)
  end

  it "rotates a token in place" do
    original = described_class.create_for_user!(user)
    original_token = original.token

    rotated = described_class.regenerate_for_user!(user)

    expect(rotated.id).to eq(original.id)
    expect(rotated.token).not_to eq(original_token)
  end

  it "is deleted with its user" do
    token = described_class.create_for_user!(user)

    user.destroy!

    expect(described_class.exists?(token.id)).to eq(false)
  end
end
