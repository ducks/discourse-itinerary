# frozen_string_literal: true

require "rails_helper"

describe DiscourseItinerary::Itinerary do
  fab!(:user)
  fab!(:category)
  fab!(:tag) { Fabricate(:tag, name: DiscourseItinerary::ITINERARY_TAG) }
  let(:guardian) { Guardian.new(user) }

  def trip(starts_at: "2026-09-20", ends_at: "2026-09-25", location: "Madrid")
    topic = Fabricate(:topic, category: category, tags: [tag])
    topic.custom_fields["itinerary_item_type"] = "trip"
    topic.custom_fields["itinerary_starts_at"] = starts_at
    topic.custom_fields["itinerary_ends_at"] = ends_at
    topic.custom_fields["itinerary_location"] = location
    topic.save_custom_fields
    topic
  end

  def item(parent_trip:, starts_at:, item_type: "flight", **extra)
    topic = Fabricate(:topic, category: category, tags: [tag])
    topic.custom_fields["itinerary_item_type"] = item_type
    topic.custom_fields["itinerary_parent_trip_id"] = parent_trip.id
    topic.custom_fields["itinerary_starts_at"] = starts_at
    extra.each { |k, v| topic.custom_fields["itinerary_#{k}"] = v }
    topic.save_custom_fields
    topic
  end

  describe ".trip?" do
    it "is true when itinerary_item_type is trip" do
      expect(described_class.trip?(trip)).to be true
    end

    it "is false for items with other types" do
      t = Fabricate(:topic, category: category, tags: [tag])
      t.custom_fields["itinerary_item_type"] = "flight"
      t.save_custom_fields
      expect(described_class.trip?(t)).to be false
    end

    it "is false for nil and bare topics with no custom fields" do
      expect(described_class.trip?(nil)).to be false
      expect(described_class.trip?(Fabricate(:topic))).to be false
    end
  end

  describe ".find" do
    it "returns an Itinerary wrapping a visible trip topic" do
      trip_topic = trip
      result = described_class.find(trip_topic.id, guardian: guardian)
      expect(result).to be_a(described_class)
      expect(result.id).to eq(trip_topic.id)
    end

    it "returns nil when the topic doesn't exist" do
      expect(described_class.find(999_999, guardian: guardian)).to be_nil
    end

    it "returns nil when the topic isn't a trip" do
      flight = Fabricate(:topic, category: category, tags: [tag])
      flight.custom_fields["itinerary_item_type"] = "flight"
      flight.save_custom_fields
      expect(described_class.find(flight.id, guardian: guardian)).to be_nil
    end

    it "returns nil when the guardian can't see the topic" do
      private_category = Fabricate(:private_category, group: Fabricate(:group))
      trip_topic = Fabricate(:topic, category: private_category, tags: [tag])
      trip_topic.custom_fields["itinerary_item_type"] = "trip"
      trip_topic.save_custom_fields
      expect(described_class.find(trip_topic.id, guardian: guardian)).to be_nil
    end
  end

  describe "#items" do
    it "returns items pointing at this trip, sorted by starts_at" do
      trip_topic = trip
      itinerary = described_class.find(trip_topic.id, guardian: guardian)

      later = item(parent_trip: trip_topic, starts_at: "2026-09-21T10:00")
      earlier = item(parent_trip: trip_topic, starts_at: "2026-09-20T14:30")

      expect(itinerary.items.map(&:id)).to eq([earlier.id, later.id])
    end

    it "does not return items pointing at a different trip" do
      trip_a = trip(starts_at: "2026-09-20")
      trip_b = trip(starts_at: "2026-10-01")
      itinerary_a = described_class.find(trip_a.id, guardian: guardian)

      item(parent_trip: trip_b, starts_at: "2026-10-02T09:00")

      expect(itinerary_a.items).to be_empty
    end

    it "does not return items missing a starts_at" do
      trip_topic = trip
      itinerary = described_class.find(trip_topic.id, guardian: guardian)

      orphan = Fabricate(:topic, category: category, tags: [tag])
      orphan.custom_fields["itinerary_item_type"] = "flight"
      orphan.custom_fields["itinerary_parent_trip_id"] = trip_topic.id
      orphan.save_custom_fields

      expect(itinerary.items).to be_empty
    end

    it "respects guardian visibility on the items themselves" do
      trip_topic = trip
      private_category = Fabricate(:private_category, group: Fabricate(:group))
      private_item = Fabricate(:topic, category: private_category, tags: [tag])
      private_item.custom_fields["itinerary_item_type"] = "flight"
      private_item.custom_fields["itinerary_parent_trip_id"] = trip_topic.id
      private_item.custom_fields["itinerary_starts_at"] = "2026-09-20T14:30"
      private_item.save_custom_fields

      itinerary = described_class.find(trip_topic.id, guardian: guardian)
      expect(itinerary.items).to be_empty
    end
  end
end
