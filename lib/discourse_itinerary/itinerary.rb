# frozen_string_literal: true

module DiscourseItinerary
  # A read-only wrapper around a "trip" topic — one of the topics
  # carrying `itinerary_item_type = 'trip'`.
  #
  # This is a thin abstraction on purpose. Today a trip is just a
  # Discourse Topic with specific custom fields; the wrapper exists so
  # controllers, serializers, and Ember loaders can talk about
  # `Itinerary` rather than reaching into `topic.custom_fields` from
  # five places. If the plugin ever grows a real `itineraries` table,
  # only this file needs to swap its internals; callers keep the same
  # surface.
  #
  # Mutation (create/update/delete) still flows through Discourse's
  # composer / PostRevisor path. The wrapper is intentionally
  # read-only.
  class Itinerary
    TRIP_TYPE = "trip"

    # Find a trip by topic ID, returning nil if the topic doesn't
    # exist, isn't a trip, or isn't visible to the guardian.
    def self.find(id, guardian:)
      topic = Topic.find_by(id: id)
      return nil unless topic
      return nil unless guardian.can_see?(topic)
      return nil unless trip?(topic)
      new(topic, guardian: guardian)
    end

    # Predicate: is this topic an itinerary trip?
    def self.trip?(topic)
      topic&.custom_fields&.[]("itinerary_item_type") == TRIP_TYPE
    end

    attr_reader :topic

    def initialize(topic, guardian:)
      @topic = topic
      @guardian = guardian
    end

    def id
      @topic.id
    end

    def title
      @topic.title
    end

    def slug
      @topic.slug
    end

    def url
      "/t/#{@topic.slug}/#{@topic.id}"
    end

    def category
      @topic.category
    end

    def starts_at
      cf("itinerary_starts_at")
    end

    def ends_at
      cf("itinerary_ends_at")
    end

    def location
      cf("itinerary_location")
    end

    # The non-trip topics that point at this trip via
    # `itinerary_parent_trip_id`, sorted by their `itinerary_starts_at`
    # value (lexical sort on ISO-8601 strings — correct for the format
    # the composer writes).
    def items
      Topic
        .secured(@guardian)
        .joins(:tags)
        .where(tags: { name: DiscourseItinerary::ITINERARY_TAG })
        .joins(
          "INNER JOIN topic_custom_fields parent " \
            "ON parent.topic_id = topics.id " \
            "AND parent.name = 'itinerary_parent_trip_id'",
        )
        .where("parent.value = ?", id.to_s)
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

    private

    def cf(key)
      @topic.custom_fields[key].presence
    end
  end
end
