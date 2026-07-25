# frozen_string_literal: true

require "rails_helper"

describe ItineraryController, type: :request do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category)

  before do
    SiteSetting.itinerary_enabled = true
    SiteSetting.itinerary_category_id = category.id
  end

  def trip(starts_at: "2026-09-20", category: self.category, title: nil, user: self.user)
    attrs = {
      category: category,
      title: title || "Itinerary trip fixture #{SecureRandom.hex(4)}",
      user: user,
    }
    topic = Fabricate(:topic, **attrs)
    topic.custom_fields["itinerary_item_type"] = "trip"
    topic.custom_fields["itinerary_starts_at"] = starts_at
    topic.custom_fields["itinerary_ends_at"] = "2026-09-25"
    topic.custom_fields["itinerary_location"] = "Madrid"
    topic.save_custom_fields
    topic
  end

  def item(parent_trip:, starts_at:, item_type: "flight", **extra)
    topic =
      Fabricate(:topic, category: category, title: "Itinerary item fixture #{SecureRandom.hex(4)}")
    topic.custom_fields["itinerary_item_type"] = item_type
    topic.custom_fields["itinerary_parent_trip_id"] = parent_trip.id
    topic.custom_fields["itinerary_starts_at"] = starts_at
    extra.each { |k, v| topic.custom_fields["itinerary_#{k}"] = v }
    topic.save_custom_fields
    topic
  end

  describe "#index (GET /itinerary/trips)" do
    it "returns every visible trip in the configured category sorted by starts_at" do
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

    it "returns visible trips created by other users for collaborative authoring" do
      other_user = Fabricate(:user)
      mine = Fabricate(:topic, category: category, user: user)
      theirs = Fabricate(:topic, category: category, user: other_user)

      [mine, theirs].each_with_index do |topic, index|
        topic.custom_fields["itinerary_item_type"] = "trip"
        topic.custom_fields["itinerary_starts_at"] = "2026-09-2#{index}"
        topic.save_custom_fields
      end

      sign_in(user)
      get "/itinerary/trips.json", params: { category_id: category.id }

      ids = response.parsed_body["trips"].map { |t| t["id"] }
      expect(ids).to eq([mine.id, theirs.id])
    end

    it "returns 404 when category_id is not the configured category" do
      other_category = Fabricate(:category)

      sign_in(user)
      get "/itinerary/trips.json", params: { category_id: other_category.id }

      expect(response.status).to eq(404)
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

    it "returns 404 when the configured category has been deleted" do
      configured_id = category.id
      category.destroy!
      SiteSetting.itinerary_category_id = configured_id

      sign_in(user)
      get "/itinerary/trips.json"

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

    it "paginates large trip lists and reports the next page" do
      stub_const(ItineraryController, :TRIPS_PER_PAGE, 2) do
        first = trip(starts_at: "2026-09-20")
        second = trip(starts_at: "2026-09-21")
        third = trip(starts_at: "2026-09-22")

        sign_in(user)
        get "/itinerary/trips.json"

        expect(response.parsed_body["trips"].map { |entry| entry["id"] }).to eq(
          [first.id, second.id],
        )
        expect(response.parsed_body["meta"]).to eq("has_more" => true, "next_page" => 1)

        get "/itinerary/trips.json", params: { page: 1 }

        expect(response.parsed_body["trips"].map { |entry| entry["id"] }).to eq([third.id])
        expect(response.parsed_body["meta"]).to eq("has_more" => false, "next_page" => nil)
      end
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
      flight =
        Fabricate(
          :topic,
          category: category,
          title: "Itinerary flight fixture #{SecureRandom.hex(4)}",
        )
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

  describe "GET /itinerary/trips/:id/ics" do
    it "returns an iCalendar document with one event per item" do
      t = trip
      item(
        parent_trip: t,
        starts_at: "2026-09-20T14:30",
        item_type: "flight",
        origin: "PDX",
        destination: "MAD",
      )
      item(
        parent_trip: t,
        starts_at: "2026-09-21",
        item_type: "hotel",
        name: "Artrip",
        location: "Madrid",
      )

      sign_in(user)
      get "/itinerary/trips/#{t.id}/ics"

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/calendar")
      expect(response.body).to start_with("BEGIN:VCALENDAR\r\n")
      expect(response.body.scan("BEGIN:VEVENT").length).to eq(2)
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Disposition"]).to include(".ics")
    end

    it "returns 404 for a missing trip" do
      sign_in(user)
      get "/itinerary/trips/9999999/ics"
      expect(response.status).to eq(404)
    end

    it "returns 404 when the trip is in a category the user can't see" do
      private_category = Fabricate(:private_category, group: Fabricate(:group))
      hidden = trip(category: private_category)

      sign_in(user)
      get "/itinerary/trips/#{hidden.id}/ics"
      expect(response.status).to eq(404)
    end
  end

  describe "POST /itinerary/trips/:id/share" do
    it "creates and returns a share token on first call" do
      t = trip
      sign_in(user)
      post "/itinerary/trips/#{t.id}/share"

      expect(response.status).to eq(200)
      body = response.parsed_body
      expect(body["token"]).to be_present
      expect(body["url"]).to include("/itinerary/shared/")
      expect(ItineraryShareToken.where(topic_id: t.id).count).to eq(1)
      expect(ItineraryShareToken.for_topic(t.id).created_by).to eq(user)
    end

    it "returns the same token on repeat calls" do
      t = trip
      sign_in(user)
      post "/itinerary/trips/#{t.id}/share"
      first = response.parsed_body["token"]
      post "/itinerary/trips/#{t.id}/share"
      second = response.parsed_body["token"]

      expect(first).to eq(second)
      expect(ItineraryShareToken.where(topic_id: t.id).count).to eq(1)
    end

    it "rejects a signed-in viewer who cannot edit the trip" do
      t = trip(user: Fabricate(:user))
      sign_in(user)

      post "/itinerary/trips/#{t.id}/share"

      expect(response.status).to eq(403)
      expect(ItineraryShareToken.where(topic_id: t.id)).to be_empty
    end

    it "requires a logged-in user" do
      t = trip

      post "/itinerary/trips/#{t.id}/share"

      expect(response.status).to eq(403)
      expect(ItineraryShareToken.where(topic_id: t.id)).to be_empty
    end
  end

  describe "POST /itinerary/trips/:id/share/regenerate" do
    it "rotates the token, invalidating the previous one" do
      t = trip
      sign_in(user)
      post "/itinerary/trips/#{t.id}/share"
      first = response.parsed_body["token"]
      post "/itinerary/trips/#{t.id}/share/regenerate"
      second = response.parsed_body["token"]

      expect(second).not_to eq(first)
      expect(ItineraryShareToken.where(topic_id: t.id).count).to eq(1)
      expect(ItineraryShareToken.for_topic(t.id).created_by).to eq(user)
      get "/itinerary/shared/#{first}"
      expect(response.status).to eq(404)
    end

    it "does not let a viewer invalidate an existing share link" do
      t = trip
      sign_in(user)
      post "/itinerary/trips/#{t.id}/share"
      original = response.parsed_body["token"]

      sign_in(Fabricate(:user))
      post "/itinerary/trips/#{t.id}/share/regenerate"

      expect(response.status).to eq(403)
      expect(ItineraryShareToken.for_topic(t.id).token).to eq(original)
    end
  end

  describe "GET /itinerary/shared/:token" do
    it "renders the read-only view without a session" do
      t = trip
      item(parent_trip: t, starts_at: "2026-09-20T14:30", item_type: "flight")
      sign_in(user)
      post "/itinerary/trips/#{t.id}/share"
      token = response.parsed_body["token"]

      sign_out
      get "/itinerary/shared/#{token}"

      expect(response.status).to eq(200)
      expect(response.body).to include(t.title)
    end

    it "404s on an unknown token" do
      get "/itinerary/shared/notarealtoken"
      expect(response.status).to eq(404)
    end
  end
end
