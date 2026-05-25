# frozen_string_literal: true

require "rails_helper"

describe DiscourseItinerary::TripItemFinder do
  fab!(:user)
  fab!(:category)
  let(:guardian) { Guardian.new(user) }

  def trip
    topic = Fabricate(:topic, category: category)
    topic.custom_fields["itinerary_item_type"] = "trip"
    topic.custom_fields["itinerary_starts_at"] = "2026-09-20"
    topic.save_custom_fields
    topic
  end

  def item(parent_trip:, starts_at:, item_type: "flight", category: self.category)
    topic = Fabricate(:topic, category: category)
    topic.custom_fields["itinerary_item_type"] = item_type
    topic.custom_fields["itinerary_parent_trip_id"] = parent_trip.id
    topic.custom_fields["itinerary_starts_at"] = starts_at
    topic.save_custom_fields
    topic
  end

  describe "#call" do
    it "returns items pointing at the given trip, sorted by starts_at" do
      trip_topic = trip
      later = item(parent_trip: trip_topic, starts_at: "2026-09-21T10:00")
      earlier = item(parent_trip: trip_topic, starts_at: "2026-09-20T14:30")

      result = described_class.new(trip: trip_topic, guardian: guardian).call

      expect(result.map(&:id)).to eq([earlier.id, later.id])
    end

    it "excludes items pointing at a different trip" do
      trip_a = trip
      trip_b = trip
      item(parent_trip: trip_b, starts_at: "2026-09-20T14:30")

      result = described_class.new(trip: trip_a, guardian: guardian).call
      expect(result).to be_empty
    end

    it "excludes items without a starts_at value" do
      trip_topic = trip
      orphan = Fabricate(:topic, category: category)
      orphan.custom_fields["itinerary_item_type"] = "flight"
      orphan.custom_fields["itinerary_parent_trip_id"] = trip_topic.id
      orphan.save_custom_fields

      result = described_class.new(trip: trip_topic, guardian: guardian).call
      expect(result).to be_empty
    end

    it "respects guardian visibility on items in private categories" do
      trip_topic = trip
      private_category = Fabricate(:private_category, group: Fabricate(:group))
      item(parent_trip: trip_topic, starts_at: "2026-09-20T14:30", category: private_category)

      result = described_class.new(trip: trip_topic, guardian: guardian).call
      expect(result).to be_empty
    end
  end
end
