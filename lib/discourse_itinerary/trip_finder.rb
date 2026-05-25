# frozen_string_literal: true

module DiscourseItinerary
  # Finds trip topics — those carrying the itinerary tag with
  # `itinerary_item_type = 'trip'`. Optionally scoped to one category.
  #
  # Returns plain Topic records, guardian-secured for visibility.
  # Callers wrap them in DiscourseItinerary::Itinerary if they need
  # the full read interface.
  #
  # Sort order: by `itinerary_starts_at` ascending. Trips without a
  # starts_at value sort last (in arbitrary order among themselves).
  class TripFinder
    def initialize(guardian:, category: nil)
      @guardian = guardian
      @category = category
    end

    def call
      scope =
        Topic
          .secured(@guardian)
          .joins(:tags)
          .where(tags: { name: DiscourseItinerary::ITINERARY_TAG })
          .joins(
            "INNER JOIN topic_custom_fields type_cf " \
              "ON type_cf.topic_id = topics.id " \
              "AND type_cf.name = 'itinerary_item_type'",
          )
          .where("type_cf.value = ?", DiscourseItinerary::Itinerary::TRIP_TYPE)
          .joins(
            "LEFT JOIN topic_custom_fields starts_cf " \
              "ON starts_cf.topic_id = topics.id " \
              "AND starts_cf.name = 'itinerary_starts_at'",
          )
          .order(Arel.sql("starts_cf.value ASC NULLS LAST"))
          .includes(:_custom_fields)

      scope = scope.where(category_id: @category.id) if @category
      scope.to_a
    end
  end
end
