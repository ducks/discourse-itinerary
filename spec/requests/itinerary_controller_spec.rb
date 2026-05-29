# frozen_string_literal: true

require "rails_helper"

describe ItineraryController, type: :request do
  fab!(:user)
  fab!(:category)

  before { SiteSetting.itinerary_enabled = true }

  def trip(starts_at: "2026-09-20", category: self.category, title: nil)
    attrs = { category: category }
    attrs[:title] = title if title
    topic = Fabricate(:topic, **attrs)
    topic.custom_fields["itinerary_item_type"] = "trip"
    topic.custom_fields["itinerary_starts_at"] = starts_at
    topic.custom_fields["itinerary_ends_at"] = "2026-09-25"
    topic.custom_fields["itinerary_location"] = "Madrid"
    topic.save_custom_fields
    topic
  end

  def item(parent_trip:, starts_at:, item_type: "flight", **extra)
    topic = Fabricate(:topic, category: category)
    topic.custom_fields["itinerary_item_type"] = item_type
    topic.custom_fields["itinerary_parent_trip_id"] = parent_trip.id
    topic.custom_fields["itinerary_starts_at"] = starts_at
    extra.each { |k, v| topic.custom_fields["itinerary_#{k}"] = v }
    topic.save_custom_fields
    topic
  end

  describe "#index (GET /itinerary/trips)" do
    it "returns every visible trip sorted by starts_at" do
      later = trip(starts_at: "2026-10-01", title: "Lisbon vacation October 2026")
      earlier = trip(starts_at: "2026-09-20", title: "Madrid working trip September")

      sign_in(user)
      get "/itinerary/trips.json"

      expect(response.status).to eq(200)
      ids = response.parsed_body["trips"].map { |t| t["id"] }
      expect(ids).to eq([earlier.id, later.id])
    end

    it "filters by category_id when provided" do
      other_category = Fabricate(:category)
      in_target = trip(category: category)
      trip(category: other_category)

      sign_in(user)
      get "/itinerary/trips.json", params: { category_id: category.id }

      ids = response.parsed_body["trips"].map { |t| t["id"] }
      expect(ids).to eq([in_target.id])
    end

    it "returns 404 when category_id points at a category the user can't see" do
      private_category = Fabricate(:private_category, group: Fabricate(:group))

      sign_in(user)
      get "/itinerary/trips.json", params: { category_id: private_category.id }

      expect(response.status).to eq(404)
    end

    it "returns 404 when category_id doesn't exist" do
      sign_in(user)
      get "/itinerary/trips.json", params: { category_id: 999_999 }
      expect(response.status).to eq(404)
    end

    it "excludes non-trip itinerary topics" do
      trip_topic = trip
      item(parent_trip: trip_topic, starts_at: "2026-09-20T14:30")

      sign_in(user)
      get "/itinerary/trips.json"

      ids = response.parsed_body["trips"].map { |t| t["id"] }
      expect(ids).to eq([trip_topic.id])
    end
  end

  describe "#show (GET /itinerary/trips/:id)" do
    it "returns the trip and its items sorted by starts_at" do
      trip_topic = trip
      later = item(parent_trip: trip_topic, starts_at: "2026-09-21T10:00")
      earlier =
        item(
          parent_trip: trip_topic,
          starts_at: "2026-09-20T14:30",
          origin: "PDX",
          destination: "MAD",
        )

      sign_in(user)
      get "/itinerary/trips/#{trip_topic.id}.json"

      expect(response.status).to eq(200)
      body = response.parsed_body
      expect(body["trip"]["id"]).to eq(trip_topic.id)
      expect(body["trip"]["title"]).to eq(trip_topic.title)
      expect(body["trip"]["location"]).to eq("Madrid")
      expect(body["items"].map { |i| i["id"] }).to eq([earlier.id, later.id])
      expect(body["items"].first["origin"]).to eq("PDX")
    end

    it "returns 404 when the trip doesn't exist" do
      sign_in(user)
      get "/itinerary/trips/999999.json"
      expect(response.status).to eq(404)
    end

    it "returns 404 when the topic exists but isn't a trip" do
      flight = Fabricate(:topic, category: category)
      flight.custom_fields["itinerary_item_type"] = "flight"
      flight.save_custom_fields

      sign_in(user)
      get "/itinerary/trips/#{flight.id}.json"
      expect(response.status).to eq(404)
    end

    it "returns 404 when the trip is in a category the user can't see" do
      private_category = Fabricate(:private_category, group: Fabricate(:group))
      hidden = trip(category: private_category)

      sign_in(user)
      get "/itinerary/trips/#{hidden.id}.json"
      expect(response.status).to eq(404)
    end
  end

  describe "GET /itinerary/trips/:id.ics" do
    it "returns an iCalendar document with one event per item" do
      t = trip
      item(parent_trip: t, starts_at: "2026-09-20T14:30", item_type: "flight",
           origin: "PDX", destination: "MAD")
      item(parent_trip: t, starts_at: "2026-09-21", item_type: "hotel",
           name: "Artrip", location: "Madrid")

      sign_in(user)
      get "/itinerary/trips/#{t.id}.ics"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/calendar")
      expect(response.body).to start_with("BEGIN:VCALENDAR\r\n")
      expect(response.body.scan("BEGIN:VEVENT").length).to eq(2)
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Disposition"]).to include(".ics")
    end

    it "returns 404 for a missing trip" do
      sign_in(user)
      get "/itinerary/trips/9999999.ics"
      expect(response.status).to eq(404)
    end

    it "returns 404 when the trip is in a category the user can't see" do
      private_category = Fabricate(:private_category, group: Fabricate(:group))
      hidden = trip(category: private_category)

      sign_in(user)
      get "/itinerary/trips/#{hidden.id}.ics"
      expect(response.status).to eq(404)
    end
  end
end
