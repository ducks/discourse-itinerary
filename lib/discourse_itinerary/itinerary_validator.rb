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
      validate_timezones
      validate_dates
      validate_cost
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

      return if starts_at.blank? || ends_at.blank?
      return unless valid_date?(starts_at) && valid_date?(ends_at)
      return unless timezones_valid?

      start_value = chronological_value(starts_at, value("itinerary_start_timezone"))
      end_value = chronological_value(ends_at, value("itinerary_end_timezone"))
      @errors << "Itinerary start has an invalid local time for its timezone." unless start_value
      @errors << "Itinerary end has an invalid local time for its timezone." unless end_value
      return unless start_value && end_value

      @errors << "Itinerary end must not be before its start." if end_value < start_value
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

    def validate_timezones
      {
        "start" => value("itinerary_start_timezone"),
        "end" => value("itinerary_end_timezone"),
      }.each do |label, timezone|
        next if timezone.blank? || DiscourseItinerary.valid_timezone?(timezone)

        @errors << "Itinerary #{label} timezone is invalid."
      end
    end

    def timezones_valid?
      %w[itinerary_start_timezone itinerary_end_timezone].all? do |field|
        timezone = value(field)
        timezone.blank? || DiscourseItinerary.valid_timezone?(timezone)
      end
    end

    def chronological_value(value, timezone)
      parsed = DateTime.iso8601(value)
      return parsed.to_time.to_f if !value.include?("T") || timezone.blank?

      local =
        Time.utc(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute, parsed.second)
      TZInfo::Timezone.get(timezone).local_to_utc(local).to_f
    rescue ArgumentError, TZInfo::AmbiguousTime, TZInfo::PeriodNotFound
      nil
    end

    def validate_cost
      amount = value("itinerary_cost_amount")
      currency = value("itinerary_cost_currency")
      if amount.present? != currency.present?
        @errors << "Itinerary cost amount and currency must be provided together."
      end

      if amount.present? && !/\A-?\d+(\.\d+)?\z/.match?(amount)
        @errors << "Itinerary cost amount must be a decimal such as 842.50."
      end
      if currency.present? && !/\A[A-Z]{3}\z/.match?(currency)
        @errors << "Itinerary cost currency must be three uppercase letters such as USD."
      end
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
