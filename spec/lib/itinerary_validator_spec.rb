# frozen_string_literal: true

require "rails_helper"

describe DiscourseItinerary::ItineraryValidator do
  fab!(:user)
  fab!(:category)
  let(:guardian) { Guardian.new(user) }

  before { SiteSetting.itinerary_category_id = category.id }

  def validate(fields = nil, category_id: category.id, acting_guardian: guardian, **keyword_fields)
    fields ||= keyword_fields
    described_class.new(fields: fields, category_id: category_id, guardian: acting_guardian).call
  end

  def trip(category: self.category)
    topic = Fabricate(:topic, category: category)
    topic.custom_fields["itinerary_item_type"] = "trip"
    topic.save_custom_fields
    topic
  end

  it "accepts a valid trip" do
    errors =
      validate(
        itinerary_item_type: "trip",
        itinerary_starts_at: "2026-09-20",
        itinerary_ends_at: "2026-09-25",
      )

    expect(errors).to be_empty
  end

  it "accepts a valid item linked to a visible trip" do
    parent = trip

    errors =
      validate(
        itinerary_item_type: "flight",
        itinerary_parent_trip_id: parent.id,
        itinerary_starts_at: "2026-09-20T14:30",
        itinerary_status: "booked",
      )

    expect(errors).to be_empty
  end

  it "rejects itinerary fields outside the configured category" do
    other = Fabricate(:category)

    errors = validate({ itinerary_item_type: "trip" }, category_id: other.id)

    expect(errors).to include(
      "Itinerary fields can only be used in the configured itinerary category.",
    )
  end

  it "rejects unknown types and statuses" do
    errors = validate(itinerary_item_type: "spaceflight", itinerary_status: "lost")

    expect(errors).to include(
      "Unknown itinerary item type: spaceflight.",
      "Unknown itinerary status: lost.",
    )
  end

  it "rejects malformed and reversed dates" do
    malformed = validate(itinerary_item_type: "trip", itinerary_starts_at: "next Tuesday")
    reversed =
      validate(
        itinerary_item_type: "trip",
        itinerary_starts_at: "2026-09-25",
        itinerary_ends_at: "2026-09-20",
      )

    expect(malformed).to include("Itinerary start has an invalid date format.")
    expect(reversed).to include("Itinerary end must not be before its start.")
  end

  it "compares cross-timezone dates as actual instants" do
    parent = trip
    errors =
      validate(
        itinerary_item_type: "flight",
        itinerary_parent_trip_id: parent.id,
        itinerary_starts_at: "2026-09-20T18:00",
        itinerary_start_timezone: "Asia/Tokyo",
        itinerary_ends_at: "2026-09-20T11:00",
        itinerary_end_timezone: "America/Los_Angeles",
      )

    expect(errors).to be_empty
  end

  it "rejects an end that is earlier after converting both timezones" do
    parent = trip
    errors =
      validate(
        itinerary_item_type: "flight",
        itinerary_parent_trip_id: parent.id,
        itinerary_starts_at: "2026-09-20T18:00",
        itinerary_start_timezone: "America/Los_Angeles",
        itinerary_ends_at: "2026-09-20T11:00",
        itinerary_end_timezone: "Asia/Tokyo",
      )

    expect(errors).to include("Itinerary end must not be before its start.")
  end

  it "rejects invalid timezones and nonexistent local times" do
    invalid_zone =
      validate(
        itinerary_item_type: "trip",
        itinerary_starts_at: "2026-09-20T09:00",
        itinerary_start_timezone: "Mars/Olympus_Mons",
      )
    daylight_gap =
      validate(
        itinerary_item_type: "trip",
        itinerary_starts_at: "2026-03-08T02:30",
        itinerary_start_timezone: "America/Los_Angeles",
        itinerary_ends_at: "2026-03-08T04:00",
        itinerary_end_timezone: "America/Los_Angeles",
      )

    expect(invalid_zone).to include("Itinerary start timezone is invalid.")
    expect(daylight_gap).to include("Itinerary start has an invalid local time for its timezone.")
  end

  it "requires cost amount and currency to be supplied together" do
    amount_only = validate(itinerary_item_type: "trip", itinerary_cost_amount: "100.00")
    currency_only = validate(itinerary_item_type: "trip", itinerary_cost_currency: "USD")

    expect(amount_only).to include("Itinerary cost amount and currency must be provided together.")
    expect(currency_only).to include(
      "Itinerary cost amount and currency must be provided together.",
    )
  end

  it "rejects malformed cost values before topic creation" do
    errors =
      validate(
        itinerary_item_type: "trip",
        itinerary_cost_amount: "1,240.50",
        itinerary_cost_currency: "usd",
      )

    expect(errors).to include(
      "Itinerary cost amount must be a decimal such as 842.50.",
      "Itinerary cost currency must be three uppercase letters such as USD.",
    )
  end

  it "requires items to have a start and valid parent" do
    errors = validate(itinerary_item_type: "hotel", itinerary_parent_trip_id: "garbage")

    expect(errors).to include(
      "An itinerary item must have a start date.",
      "The selected parent is not an itinerary trip.",
    )
  end

  it "rejects a parent in a different category" do
    parent = trip(category: Fabricate(:category))

    errors =
      validate(
        itinerary_item_type: "note",
        itinerary_parent_trip_id: parent.id,
        itinerary_starts_at: "2026-09-20T09:00",
      )

    expect(errors).to include("An itinerary item and its parent trip must be in the same category.")
  end

  it "rejects a parent the acting user cannot see" do
    private_category = Fabricate(:private_category, group: Fabricate(:group))
    parent = trip(category: private_category)

    errors =
      validate(
        {
          itinerary_item_type: "note",
          itinerary_parent_trip_id: parent.id,
          itinerary_starts_at: "2026-09-20T09:00",
        },
        category_id: private_category.id,
      )

    expect(errors).to include("The selected parent trip is not visible.")
  end

  it "rejects a parent on a trip topic" do
    errors = validate(itinerary_item_type: "trip", itinerary_parent_trip_id: trip.id)

    expect(errors).to include("A trip cannot have a parent trip.")
  end
end
