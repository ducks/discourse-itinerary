# frozen_string_literal: true

require "rails_helper"

describe ItineraryShareToken do
  fab!(:user)
  fab!(:other_user, :user)
  fab!(:topic)

  describe ".create_for_topic!" do
    it "is idempotent and records who issued the link" do
      first = described_class.create_for_topic!(topic.id, created_by: user)
      second = described_class.create_for_topic!(topic.id, created_by: other_user)

      expect(second).to eq(first)
      expect(second.created_by).to eq(user)
      expect(described_class.where(topic_id: topic.id).count).to eq(1)
    end
  end

  describe ".regenerate_for_topic!" do
    it "rotates in place so there is no window without a valid row" do
      original = described_class.create_for_topic!(topic.id, created_by: user)
      original_token = original.token

      rotated = described_class.regenerate_for_topic!(topic.id, created_by: other_user)

      expect(rotated.id).to eq(original.id)
      expect(rotated.token).not_to eq(original_token)
      expect(rotated.created_by).to eq(other_user)
    end
  end

  it "is deleted automatically with its trip topic" do
    token = described_class.create_for_topic!(topic.id, created_by: user)

    topic.destroy!

    expect(described_class.exists?(token.id)).to eq(false)
  end
end
