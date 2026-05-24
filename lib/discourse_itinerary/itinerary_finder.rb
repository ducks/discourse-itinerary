# frozen_string_literal: true

module DiscourseItinerary
  # Finds itinerary topics for a category, sorted chronologically by the
  # `itinerary_starts_at` custom field.
  #
  # A topic is an itinerary item if:
  #   1. It's in the target category
  #   2. It carries the `itinerary` tag
  #   3. It has a non-blank `itinerary_starts_at` custom field value
  #
  # `starts_at` is stored as an ISO-8601 string and sorted lexically,
  # which is correct for properly-formatted timestamps.
  class ItineraryFinder
    def initialize(category:, guardian:)
      @category = category
      @guardian = guardian
    end

    def call
      Topic
        .secured(@guardian)
        .where(category_id: @category.id)
        .joins(:tags).where(tags: { name: DiscourseItinerary::ITINERARY_TAG })
        .joins(
          "INNER JOIN topic_custom_fields starts " \
          "ON starts.topic_id = topics.id " \
          "AND starts.name = 'itinerary_starts_at'"
        )
        .where("starts.value IS NOT NULL AND starts.value <> ''")
        .order('starts.value ASC')
        .includes(:_custom_fields)
        .to_a
    end
  end
end
