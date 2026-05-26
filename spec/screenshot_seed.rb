# frozen_string_literal: true

# Seeds three realistic trips into the itinerary category so screenshot
# captures from discourse-plugin-screenshots render meaningful content
# instead of empty states.
#
# Run inside the Rails test environment by the screenshot tool. Should
# be idempotent on title so re-running the same screenshot job doesn't
# pile up duplicates.
#
# Targets `/itinerary/2` for the timeline screenshot, which corresponds
# to the first trip created here once the itinerary category and its
# "About" topic are in place.

# Make sure the plugin's category is provisioned before we try to use
# it. In a fresh test DB the after_initialize hook may not have fired
# yet (or it ran before any user existed).
DiscourseItinerary::CategoryProvisioner.ensure_category!
category = DiscourseItinerary.category
raise "no itinerary category to seed into" unless category

user = Discourse.system_user

# Lowering the title-length and entropy floors temporarily so the
# realistic-but-short flight titles ("Flight: PDX -> LIS") clear the
# validators. The screenshot run cares about visual output, not
# enforcing community-quality heuristics.
original_min = SiteSetting.min_topic_title_length
SiteSetting.min_topic_title_length = 5 if original_min > 5

def upsert(user:, category:, title:, raw:, fields:)
  existing = Topic.where(category_id: category.id, title: title).first
  if existing
    fields.each { |k, v| existing.custom_fields[k.to_s] = v }
    existing.save_custom_fields
    return existing
  end

  pc =
    PostCreator.new(
      user,
      title: title,
      raw: raw,
      category: category.id,
      skip_validations: true,
      **fields,
    )
  post = pc.create
  raise "create failed for #{title.inspect}: #{pc.errors.full_messages.join("; ")}" unless post

  post.topic
end

trips = [
  {
    trip: {
      title: "Lisbon long weekend, June 2026",
      raw: "Four nights in Lisbon, plenty of time for pastries.",
      starts_at: "2026-06-12",
      ends_at: "2026-06-16",
      location: "Lisbon, Portugal",
    },
    items: [
      {
        title: "Flight: PDX -> LIS",
        raw: "- Route: PDX -> LIS\n- Confirmation: TAP9F2K\n- Status: booked",
        type: "flight",
        starts_at: "2026-06-12T13:45",
        ends_at: "2026-06-13T11:20",
        origin: "PDX",
        destination: "LIS",
        confirmation_code: "TAP9F2K",
        status: "booked",
      },
      {
        title: "Hotel: Memmo Alfama",
        raw: "- Name: Memmo Alfama\n- Location: Alfama, Lisbon\n- Status: booked",
        type: "hotel",
        starts_at: "2026-06-13T15:00",
        ends_at: "2026-06-16T11:00",
        name: "Memmo Alfama",
        location: "Alfama, Lisbon",
        confirmation_code: "BK-44218",
        status: "booked",
      },
      {
        title: "Event: Fado dinner at Clube de Fado",
        raw: "- Location: Clube de Fado, Alfama\n- Status: booked",
        type: "event",
        starts_at: "2026-06-13T20:30",
        name: "Clube de Fado",
        location: "Alfama, Lisbon",
        status: "booked",
      },
      {
        title: "Transfer: Lisbon -> Sintra",
        raw: "- Route: Lisbon -> Sintra (CP train)\n- Status: planned",
        type: "transfer",
        starts_at: "2026-06-14T09:15",
        ends_at: "2026-06-14T10:00",
        origin: "Lisbon",
        destination: "Sintra",
        status: "planned",
      },
      {
        title: "Event: Pena Palace tour",
        raw: "- Location: Pena Palace, Sintra\n- Status: planned",
        type: "event",
        starts_at: "2026-06-14T11:00",
        name: "Pena Palace",
        location: "Sintra",
        status: "planned",
      },
      {
        title: "Flight: LIS -> PDX",
        raw: "- Route: LIS -> PDX\n- Confirmation: TAP9F2K\n- Status: booked",
        type: "flight",
        starts_at: "2026-06-16T14:10",
        ends_at: "2026-06-16T22:40",
        origin: "LIS",
        destination: "PDX",
        confirmation_code: "TAP9F2K",
        status: "booked",
      },
    ],
  },
  {
    trip: {
      title: "Tokyo team offsite, September 2026",
      raw: "Five days in Tokyo with the engineering team.",
      starts_at: "2026-09-08",
      ends_at: "2026-09-14",
      location: "Tokyo, Japan",
    },
    items: [
      {
        title: "Flight: PDX -> HND",
        raw: "- Route: PDX -> HND (via SEA)\n- Status: booked",
        type: "flight",
        starts_at: "2026-09-08T10:30",
        ends_at: "2026-09-09T14:25",
        origin: "PDX",
        destination: "HND",
        confirmation_code: "ANA77H4",
        status: "booked",
      },
      {
        title: "Hotel: Cerulean Tower Tokyu",
        raw: "- Name: Cerulean Tower Tokyu\n- Location: Shibuya, Tokyo",
        type: "hotel",
        starts_at: "2026-09-09T16:00",
        ends_at: "2026-09-13T11:00",
        name: "Cerulean Tower Tokyu",
        location: "Shibuya, Tokyo",
        confirmation_code: "H-9921",
        status: "booked",
      },
      {
        title: "Train: Tokyo -> Kamakura",
        raw: "- Route: Tokyo -> Kamakura (JR Yokosuka line)\n- Status: planned",
        type: "train",
        starts_at: "2026-09-11T08:45",
        ends_at: "2026-09-11T09:50",
        origin: "Tokyo",
        destination: "Kamakura",
        status: "planned",
      },
    ],
  },
  {
    trip: {
      title: "BC coast road trip, December 2026",
      raw: "Driving from Portland up through Vancouver and Tofino.",
      starts_at: "2026-12-20",
      ends_at: "2026-12-28",
      location: "British Columbia",
    },
    items: [
      {
        title: "Hotel: Sylvia Hotel, Vancouver",
        raw: "- Name: Sylvia Hotel\n- Location: English Bay, Vancouver",
        type: "hotel",
        starts_at: "2026-12-20T16:00",
        ends_at: "2026-12-23T11:00",
        name: "Sylvia Hotel",
        location: "English Bay, Vancouver",
        confirmation_code: "SYL-7711",
        status: "booked",
      },
      {
        title: "Hotel: Wickaninnish Inn, Tofino",
        raw: "- Name: Wickaninnish Inn\n- Location: Chesterman Beach, Tofino",
        type: "hotel",
        starts_at: "2026-12-23T16:00",
        ends_at: "2026-12-27T11:00",
        name: "Wickaninnish Inn",
        location: "Chesterman Beach, Tofino",
        confirmation_code: "WICK-3398",
        status: "booked",
      },
    ],
  },
]

trips.each do |row|
  trip_attrs = row[:trip]
  trip =
    upsert(
      user: user,
      category: category,
      title: trip_attrs[:title],
      raw: trip_attrs[:raw],
      fields: {
        itinerary_item_type: "trip",
        itinerary_starts_at: trip_attrs[:starts_at],
        itinerary_ends_at: trip_attrs[:ends_at],
        itinerary_location: trip_attrs[:location],
      },
    )

  row[:items].each do |item|
    fields = {
      itinerary_item_type: item[:type],
      itinerary_parent_trip_id: trip.id,
      itinerary_starts_at: item[:starts_at],
    }
    fields[:itinerary_ends_at] = item[:ends_at] if item[:ends_at]
    fields[:itinerary_origin] = item[:origin] if item[:origin]
    fields[:itinerary_destination] = item[:destination] if item[:destination]
    fields[:itinerary_name] = item[:name] if item[:name]
    fields[:itinerary_location] = item[:location] if item[:location]
    fields[:itinerary_confirmation_code] = item[:confirmation_code] if item[:confirmation_code]
    fields[:itinerary_status] = item[:status] if item[:status]

    upsert(user: user, category: category, title: item[:title], raw: item[:raw], fields: fields)
  end
end

SiteSetting.min_topic_title_length = original_min
