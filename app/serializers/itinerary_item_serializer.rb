# frozen_string_literal: true

class ItineraryItemSerializer < ApplicationSerializer
  attributes :id,
             :title,
             :slug,
             :url,
             :item_type,
             :parent_trip_id,
             :starts_at,
             :ends_at,
             :origin,
             :destination,
             :location,
             :confirmation_code,
             :status

  def url
    "/t/#{object.slug}/#{object.id}"
  end

  def item_type
    cf("itinerary_item_type")
  end
  def parent_trip_id
    cf("itinerary_parent_trip_id")&.to_i
  end
  def starts_at
    cf("itinerary_starts_at")
  end
  def ends_at
    cf("itinerary_ends_at")
  end
  def origin
    cf("itinerary_origin")
  end
  def destination
    cf("itinerary_destination")
  end
  def location
    cf("itinerary_location")
  end
  def confirmation_code
    cf("itinerary_confirmation_code")
  end
  def status
    cf("itinerary_status")
  end

  private

  # Returns the custom field value or nil if blank. Custom fields often
  # come back as empty strings when cleared rather than NULL, so we
  # normalize here.
  def cf(key)
    object.custom_fields[key].presence
  end
end
