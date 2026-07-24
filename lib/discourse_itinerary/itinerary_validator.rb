# frozen_string_literal: true

module DiscourseItinerary
  # Validates the relationships and canonical values stored in itinerary
  # topic custom fields. The composer provides a friendly authoring flow, but
  # API clients and edited topics must obey the same invariants server-side.
  class ItineraryValidator
    VALID_STATUSES = %w[planned booked checked_in completed].freeze
    DATE_PATTERN = /\A\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2})?)?\z/

    def initialize(fields:, category_id:, guardian:)
      @fields = fields.with_indifferent_access
      @category_id = category_id.to_i
      @guardian = guardian
      @errors = []
    end

    def call
      return [] unless itinerary_fields_present?

      validate_category
      validate_item_type
      validate_status
      validate_dates
      validate_relationship
      @errors
    end

    private

    def itinerary_fields_present?
      DiscourseItinerary::CUSTOM_FIELDS.keys.any? { |field| @fields.key?(field) }
    end

    def value(field)
      @fields[field].presence
    end

    def validate_category
      configured = DiscourseItinerary.category
      if configured.nil?
        @errors << "The itinerary category is not configured."
      elsif @category_id != configured.id
        @errors << "Itinerary fields can only be used in the configured itinerary category."
      end
    end

    def validate_item_type
      type = value("itinerary_item_type")
      if type.blank?
        @errors << "Itinerary item type is required."
      elsif DiscourseItinerary::VALID_ITEM_TYPES.exclude?(type)
        @errors << "Unknown itinerary item type: #{type}."
      end
    end

    def validate_status
      status = value("itinerary_status")
      return if status.blank? || VALID_STATUSES.include?(status)

      @errors << "Unknown itinerary status: #{status}."
    end

    def validate_dates
      starts_at = value("itinerary_starts_at")
      ends_at = value("itinerary_ends_at")

      validate_date("start", starts_at)
      validate_date("end", ends_at)

      if starts_at.present? && ends_at.present? && valid_date?(starts_at) && valid_date?(ends_at) &&
           ends_at < starts_at
        @errors << "Itinerary end must not be before its start."
      end
    end

    def validate_date(label, date)
      return if date.blank? || valid_date?(date)

      @errors << "Itinerary #{label} has an invalid date format."
    end

    def valid_date?(date)
      return false unless DATE_PATTERN.match?(date)

      DateTime.iso8601(date)
      true
    rescue ArgumentError
      false
    end

    def validate_relationship
      type = value("itinerary_item_type")
      parent_id = value("itinerary_parent_trip_id")

      if type == DiscourseItinerary::Itinerary::TRIP_TYPE
        @errors << "A trip cannot have a parent trip." if parent_id.present?
        return
      end

      return if type.blank? || DiscourseItinerary::VALID_ITEM_TYPES.exclude?(type)

      @errors << "An itinerary item must have a start date." if value("itinerary_starts_at").blank?
      if parent_id.blank?
        @errors << "An itinerary item must belong to a trip."
        return
      end

      parent = Topic.find_by(id: strict_integer(parent_id))
      unless parent && DiscourseItinerary::Itinerary.trip?(parent)
        @errors << "The selected parent is not an itinerary trip."
        return
      end

      if parent.category_id != @category_id
        @errors << "An itinerary item and its parent trip must be in the same category."
      end
      @errors << "The selected parent trip is not visible." unless @guardian.can_see?(parent)
    end

    def strict_integer(value)
      value.is_a?(Integer) ? value : Integer(value, 10)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
