# frozen_string_literal: true

require "rails_helper"

describe DiscourseItinerary::TripFinder do
  fab!(:user)
  fab!(:category)
  let(:guardian) { Guardian.new(user) }

  before { SiteSetting.itinerary_category_id = category.id }

  def trip(starts_at: "2026-09-20", category: self.category, user: nil)
    attrs = { category: category }
    attrs[:user] = user if user
    topic = Fabricate(:topic, **attrs)
    topic.custom_fields["itinerary_item_type"] = "trip"
    topic.custom_fields["itinerary_starts_at"] = starts_at
    topic.save_custom_fields
    topic
  end

  describe "#call" do
    it "returns trip topics sorted by starts_at ascending" do
      later = trip(starts_at: "2026-10-01")
      earlier = trip(starts_at: "2026-09-20")

      result = described_class.new(guardian: guardian).call

      expect(result.map(&:id)).to eq([earlier.id, later.id])
    end

    it "excludes non-trip itinerary topics" do
      item = Fabricate(:topic, category: category)
      item.custom_fields["itinerary_item_type"] = "flight"
      item.custom_fields["itinerary_starts_at"] = "2026-09-20T14:30"
      item.save_custom_fields

      result = described_class.new(guardian: guardian).call
      expect(result).to be_empty
    end

    it "excludes topics without itinerary_item_type set" do
      bare = Fabricate(:topic, category: category)

      result = described_class.new(guardian: guardian).call
      expect(result).not_to include(bare)
    end

    it "filters by category when category is provided" do
      other_category = Fabricate(:category)
      in_target = trip(starts_at: "2026-09-20", category: category)
      trip(starts_at: "2026-09-20", category: other_category)

      result = described_class.new(guardian: guardian, category: category).call
      expect(result.map(&:id)).to eq([in_target.id])
    end

    it "defaults to the configured itinerary category" do
      other_category = Fabricate(:category)
      a = trip(starts_at: "2026-09-20", category: category)
      trip(starts_at: "2026-10-01", category: other_category)

      result = described_class.new(guardian: guardian).call
      expect(result.map(&:id)).to eq([a.id])
    end

    it "respects guardian visibility on the category" do
      private_category = Fabricate(:private_category, group: Fabricate(:group))
      trip(starts_at: "2026-09-20", category: private_category)

      result = described_class.new(guardian: guardian).call
      expect(result).to be_empty
    end

    it "sorts trips without starts_at last" do
      with_starts = trip(starts_at: "2026-09-20")
      without_starts = Fabricate(:topic, category: category)
      without_starts.custom_fields["itinerary_item_type"] = "trip"
      without_starts.save_custom_fields

      result = described_class.new(guardian: guardian).call
      expect(result.map(&:id)).to eq([with_starts.id, without_starts.id])
    end

    it "filters to trips created by a given user when created_by is provided" do
      other_user = Fabricate(:user)
      mine = trip(starts_at: "2026-09-20", user: user)
      trip(starts_at: "2026-10-01", user: other_user)

      result = described_class.new(guardian: guardian, created_by: user).call
      expect(result.map(&:id)).to eq([mine.id])
    end

    it "supports bounded pages" do
      first = trip(starts_at: "2026-09-20")
      second = trip(starts_at: "2026-09-21")
      trip(starts_at: "2026-09-22")

      result = described_class.new(guardian: guardian, limit: 1, offset: 1).call

      expect(result).to eq([second])
      expect(result).not_to include(first)
    end
  end
end
