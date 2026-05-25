# frozen_string_literal: true

require "rails_helper"

describe DiscourseItinerary::ItineraryFinder do
  fab!(:user)
  fab!(:category)
  fab!(:tag) { Fabricate(:tag, name: DiscourseItinerary::ITINERARY_TAG) }
  let(:guardian) { Guardian.new(user) }

  def itinerary_topic(starts_at:, category: self.category, **fields)
    topic = Fabricate(:topic, category: category, tags: [tag])
    topic.custom_fields["itinerary_starts_at"] = starts_at
    fields.each { |k, v| topic.custom_fields["itinerary_#{k}"] = v }
    topic.save_custom_fields
    topic
  end

  it "returns itinerary topics sorted by starts_at ascending" do
    later = itinerary_topic(starts_at: "2026-09-21T10:00", item_type: "hotel")
    earlier = itinerary_topic(starts_at: "2026-09-20T14:30", item_type: "flight")

    result = described_class.new(category: category, guardian: guardian).call

    expect(result.map(&:id)).to eq([earlier.id, later.id])
  end

  it "ignores topics without the itinerary tag" do
    untagged = Fabricate(:topic, category: category)
    untagged.custom_fields["itinerary_starts_at"] = "2026-09-20T00:00"
    untagged.save_custom_fields

    result = described_class.new(category: category, guardian: guardian).call
    expect(result).to be_empty
  end

  it "ignores topics with the tag but no starts_at value" do
    Fabricate(:topic, category: category, tags: [tag])

    result = described_class.new(category: category, guardian: guardian).call
    expect(result).to be_empty
  end

  it "ignores topics in other categories" do
    other_category = Fabricate(:category)
    itinerary_topic(starts_at: "2026-09-20T00:00", category: other_category)

    result = described_class.new(category: category, guardian: guardian).call
    expect(result).to be_empty
  end

  it "respects category read permissions" do
    private_category = Fabricate(:private_category, group: Fabricate(:group))
    itinerary_topic(starts_at: "2026-09-20T00:00", category: private_category)

    result = described_class.new(category: private_category, guardian: guardian).call

    expect(result).to be_empty
  end
end
