# frozen_string_literal: true

require "rails_helper"

describe DiscourseItinerary::TripFinder do
  fab!(:user)
  fab!(:category)
  let(:guardian) { Guardian.new(user) }

  def trip(starts_at: "2026-09-20", category: self.category)
    topic = Fabricate(:topic, category: category)
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

    it "returns trips from all categories when no category is provided" do
      other_category = Fabricate(:category)
      a = trip(starts_at: "2026-09-20", category: category)
      b = trip(starts_at: "2026-10-01", category: other_category)

      result = described_class.new(guardian: guardian).call
      expect(result.map(&:id)).to contain_exactly(a.id, b.id)
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
  end
end
