# frozen_string_literal: true

require "rails_helper"

describe ItineraryController, type: :request do
  fab!(:user)
  fab!(:category)
  fab!(:tag) { Fabricate(:tag, name: DiscourseItinerary::ITINERARY_TAG) }

  before { SiteSetting.itinerary_enabled = true }

  def make_item(starts_at:, item_type:, **extra)
    topic = Fabricate(:topic, category: category, tags: [tag])
    topic.custom_fields["itinerary_starts_at"] = starts_at
    topic.custom_fields["itinerary_item_type"] = item_type
    extra.each { |k, v| topic.custom_fields["itinerary_#{k}"] = v }
    topic.save_custom_fields
    topic
  end

  describe "#show" do
    it "renders the chronological item list as JSON" do
      make_item(starts_at: "2026-09-21T09:00", item_type: "hotel")
      make_item(
        starts_at: "2026-09-20T14:30",
        item_type: "flight",
        origin: "PDX",
        destination: "MAD",
      )

      sign_in(user)
      get "/itinerary/#{category.slug}.json"

      expect(response.status).to eq(200)
      body = response.parsed_body
      expect(body["category"]["slug"]).to eq(category.slug)
      expect(body["items"].length).to eq(2)
      expect(body["items"].first["item_type"]).to eq("flight")
      expect(body["items"].first["origin"]).to eq("PDX")
    end

    it "returns 404 for unknown categories" do
      sign_in(user)
      get "/itinerary/does-not-exist.json"
      expect(response.status).to eq(404)
    end

    it "returns 404 when the user cannot see the category" do
      private_category = Fabricate(:private_category, group: Fabricate(:group))
      sign_in(user)
      get "/itinerary/#{private_category.slug}.json"
      expect(response.status).to eq(404)
    end
  end
end
