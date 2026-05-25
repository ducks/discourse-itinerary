# frozen_string_literal: true

module DiscourseItinerary
  # Finds non-trip topics that belong to a given trip via
  # `itinerary_parent_trip_id`. Returns plain Topic records sorted by
  # `itinerary_starts_at` ascending.
  #
  # Topics with no `itinerary_starts_at` (or a blank value) are
  # excluded — they have no chronological position in the timeline.
  #
  # Lexically sorting ISO-8601 strings is correct for the canonical
  # `YYYY-MM-DDTHH:MM[:SS]` format. If a malformed date sneaks in,
  # it'll sort in the wrong place but won't blow up the query.
  class TripItemFinder
    def initialize(trip:, guardian:)
      @trip = trip
      @guardian = guardian
    end

    def call
      Topic
        .secured(@guardian)
        .joins(
          "INNER JOIN topic_custom_fields parent " \
            "ON parent.topic_id = topics.id " \
            "AND parent.name = 'itinerary_parent_trip_id'",
        )
        .where("parent.value = ?", @trip.id.to_s)
        .joins(
          "INNER JOIN topic_custom_fields starts " \
            "ON starts.topic_id = topics.id " \
            "AND starts.name = 'itinerary_starts_at'",
        )
        .where("starts.value IS NOT NULL AND starts.value <> ''")
        .order("starts.value ASC")
        .includes(:_custom_fields)
        .to_a
    end
  end
end
