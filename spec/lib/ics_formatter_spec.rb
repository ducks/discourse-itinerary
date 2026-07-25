# frozen_string_literal: true

require "rails_helper"

describe DiscourseItinerary::IcsFormatter do
  fab!(:user)
  fab!(:category)
  let(:guardian) { Guardian.new(user) }

  def make_trip(title:)
    topic = Fabricate(:topic, category: category, title: title)
    topic.custom_fields["itinerary_item_type"] = "trip"
    topic.save_custom_fields
    DiscourseItinerary::Itinerary.new(topic, guardian: guardian)
  end

  def make_item(trip:, starts_at:, **fields)
    topic =
      Fabricate(:topic, category: category, title: "Itinerary item fixture #{SecureRandom.hex(4)}")
    topic.custom_fields["itinerary_parent_trip_id"] = trip.id
    topic.custom_fields["itinerary_starts_at"] = starts_at
    fields.each { |k, v| topic.custom_fields["itinerary_#{k}"] = v }
    topic.save_custom_fields
    topic
  end

  describe "the calendar wrapper" do
    let(:trip) { make_trip(title: "Trip to Europe 2026") }

    it "wraps events in VCALENDAR with required headers" do
      flight =
        make_item(
          trip: trip,
          starts_at: "2026-09-20T14:30",
          ends_at: "2026-09-21T09:15",
          item_type: "flight",
          origin: "PDX",
          destination: "MAD",
        )

      ics = described_class.call(trip: trip, items: [flight])

      expect(ics).to start_with("BEGIN:VCALENDAR\r\n")
      expect(ics).to end_with("END:VCALENDAR\r\n")
      expect(ics).to include("VERSION:2.0")
      expect(ics).to include("PRODID:-//Discourse Itinerary//EN")
      expect(ics).to include("X-WR-CALNAME:Trip to Europe 2026")
    end

    it "uses CRLF line endings throughout" do
      flight = make_item(trip: trip, starts_at: "2026-09-20T14:30", item_type: "flight")
      ics = described_class.call(trip: trip, items: [flight])

      # No bare LF should appear in the output.
      expect(ics.scan(/(?<!\r)\n/)).to be_empty
    end
  end

  describe "event formatting" do
    let(:trip) { make_trip(title: "Trip to Europe 2026") }

    it "emits one VEVENT per item with start and end times" do
      flight =
        make_item(
          trip: trip,
          starts_at: "2026-09-20T14:30",
          ends_at: "2026-09-21T09:15",
          item_type: "flight",
          origin: "PDX",
          destination: "MAD",
        )

      ics = described_class.call(trip: trip, items: [flight])

      expect(ics.scan("BEGIN:VEVENT").length).to eq(1)
      expect(ics).to include("DTSTART:20260920T143000")
      expect(ics).to include("DTEND:20260921T091500")
      expect(ics).to include("SUMMARY:Flight PDX -> MAD")
    end

    it "skips items without a starts_at value" do
      note =
        Fabricate(
          :topic,
          category: category,
          title: "Itinerary note fixture #{SecureRandom.hex(4)}",
        )
      note.custom_fields["itinerary_parent_trip_id"] = trip.id
      note.custom_fields["itinerary_item_type"] = "note"
      note.save_custom_fields

      ics = described_class.call(trip: trip, items: [note])
      expect(ics).not_to include("BEGIN:VEVENT")
    end

    it "omits DTEND when the item has no ends_at" do
      transfer = make_item(trip: trip, starts_at: "2026-09-24T09:00", item_type: "transfer")
      ics = described_class.call(trip: trip, items: [transfer])
      expect(ics).to include("DTSTART:20260924T090000")
      expect(ics).not_to match(/^DTEND:/)
    end

    it "formats hotels with name and location in the summary" do
      hotel =
        make_item(
          trip: trip,
          starts_at: "2026-09-21",
          ends_at: "2026-09-24",
          item_type: "hotel",
          name: "Artrip",
          location: "Madrid",
        )
      ics = described_class.call(trip: trip, items: [hotel])
      expect(ics).to include("DTSTART;VALUE=DATE:20260921")
      expect(ics).to include("DTEND;VALUE=DATE:20260924")
      expect(ics).to include("SUMMARY:Hotel: Artrip (Madrid)")
    end

    it "omits confirmation codes by default while retaining status" do
      flight =
        make_item(
          trip: trip,
          starts_at: "2026-09-20T14:30",
          item_type: "flight",
          confirmation_code: "ABC123",
          status: "booked",
        )
      ics = described_class.call(trip: trip, items: [flight])
      expect(ics).to include("DESCRIPTION:Status: booked")
      expect(ics).not_to include("ABC123")
    end

    it "includes confirmation codes when the site setting explicitly enables them" do
      SiteSetting.itinerary_include_confirmation_codes_in_ics = true
      flight =
        make_item(
          trip: trip,
          starts_at: "2026-09-20T14:30",
          item_type: "flight",
          confirmation_code: "ABC123",
          status: "booked",
        )

      ics = described_class.call(trip: trip, items: [flight])

      expect(ics).to include("DESCRIPTION:Confirmation: ABC123\\nStatus: booked")
    end

    it "uses a stable UID derived from the topic id and host" do
      flight = make_item(trip: trip, starts_at: "2026-09-20T14:30", item_type: "flight")
      ics = described_class.call(trip: trip, items: [flight])

      host = Discourse.base_url.sub(%r{^https?://}, "")
      expect(ics).to include("UID:itinerary-#{flight.id}@#{host}")
    end

    it "links back to the source topic" do
      flight = make_item(trip: trip, starts_at: "2026-09-20T14:30", item_type: "flight")
      ics = described_class.call(trip: trip, items: [flight])
      expect(ics).to include("URL:#{Discourse.base_url}/t/#{flight.slug}/#{flight.id}")
    end
  end

  describe "timezones" do
    let(:trip) { make_trip(title: "Trip to Europe 2026") }

    it "tags DTSTART and DTEND with TZID when an item has timezones" do
      flight =
        make_item(
          trip: trip,
          starts_at: "2026-09-20T14:30",
          ends_at: "2026-09-20T22:15",
          start_timezone: "America/Los_Angeles",
          end_timezone: "Europe/Madrid",
          item_type: "flight",
        )

      ics = described_class.call(trip: trip, items: [flight])

      expect(ics).to include("DTSTART;TZID=America/Los_Angeles:20260920T143000")
      expect(ics).to include("DTEND;TZID=Europe/Madrid:20260920T221500")
    end

    it "emits a VTIMEZONE block for each distinct zone used" do
      flight =
        make_item(
          trip: trip,
          starts_at: "2026-09-20T14:30",
          ends_at: "2026-09-20T22:15",
          start_timezone: "America/Los_Angeles",
          end_timezone: "Europe/Madrid",
          item_type: "flight",
        )
      hotel =
        make_item(
          trip: trip,
          starts_at: "2026-09-21T15:00",
          start_timezone: "Europe/Madrid",
          end_timezone: "Europe/Madrid",
          item_type: "hotel",
        )

      ics = described_class.call(trip: trip, items: [flight, hotel])

      expect(ics).to include("BEGIN:VTIMEZONE")
      expect(ics).to include("TZID:America/Los_Angeles")
      expect(ics).to include("TZID:Europe/Madrid")
      expect(ics.scan("BEGIN:VTIMEZONE").length).to eq(2)
    end

    it "emits the daylight-saving transitions surrounding the trip" do
      event =
        make_item(
          trip: trip,
          starts_at: "2026-07-20T14:30",
          start_timezone: "America/Los_Angeles",
          item_type: "event",
        )

      ics = described_class.call(trip: trip, items: [event])

      expect(ics).to include("BEGIN:DAYLIGHT")
      expect(ics).to include("TZOFFSETFROM:-0800")
      expect(ics).to include("TZOFFSETTO:-0700")
      expect(ics).to include("BEGIN:STANDARD")
      expect(ics).to include("TZOFFSETFROM:-0700")
      expect(ics).to include("TZOFFSETTO:-0800")
    end

    it "falls back to a floating time when an item has no timezone" do
      legacy = make_item(trip: trip, starts_at: "2026-09-20T14:30", item_type: "event")
      ics = described_class.call(trip: trip, items: [legacy])
      expect(ics).to include("DTSTART:20260920T143000")
      expect(ics).not_to match(/^BEGIN:VTIMEZONE/)
    end
  end

  describe "text escaping" do
    let(:trip) { make_trip(title: "Tricky, trip; with\\backslash") }

    it "escapes commas, semicolons, backslashes, and newlines in text fields" do
      ics = described_class.call(trip: trip, items: [])
      expect(ics).to include("X-WR-CALNAME:Tricky\\, trip\\; with\\\\backslash")
    end

    it "folds long non-ASCII lines on valid UTF-8 character boundaries" do
      trip = make_trip(title: "Summer itinerary")
      trip.topic.update_column(:title, "夏の旅行計画" * 10)

      ics = described_class.call(trip: trip, items: [])
      calendar_name_lines = ics.lines.grep(/X-WR-CALNAME|^ /)

      expect(ics.valid_encoding?).to eq(true)
      expect(calendar_name_lines).to all(
        satisfy { |line| line.delete_suffix("\r\n").bytesize <= 75 },
      )
    end
  end
end
