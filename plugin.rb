# frozen_string_literal: true

# name: discourse-itinerary
# about: Renders Discourse topics in a category as a chronological travel itinerary.
# version: 0.1.0
# authors: Jake Goldsborough
# url: https://github.com/ducks/discourse-itinerary

enabled_site_setting :itinerary_enabled

module ::DiscourseItinerary
  PLUGIN_NAME = 'discourse-itinerary'

  # Topic custom field keys. Stored as strings on Discourse's
  # topic_custom_fields table.
  CUSTOM_FIELDS = %w[
    itinerary_item_type
    itinerary_starts_at
    itinerary_ends_at
    itinerary_origin
    itinerary_destination
    itinerary_location
    itinerary_confirmation_code
    itinerary_status
  ].freeze

  # The tag that marks a topic as an itinerary item. Lives in the
  # standard Discourse tag system so existing UI for tag management
  # applies to it.
  ITINERARY_TAG = 'itinerary'
end

DiscourseItinerary::CUSTOM_FIELDS.each do |field|
  register_topic_custom_field_type(field, :string)
end

after_initialize do
  require_relative 'lib/discourse_itinerary/itinerary_finder'
  require_relative 'app/serializers/itinerary_item_serializer'
  require_relative 'app/controllers/itinerary_controller'

  Discourse::Application.routes.append do
    get '/itinerary/:category_slug' => 'itinerary#show',
        defaults: { format: :json },
        constraints: { format: :json }
  end
end
