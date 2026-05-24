# frozen_string_literal: true

# name: discourse-itinerary
# about: Renders Discourse topics in a category as a chronological travel itinerary.
# version: 0.2.0
# authors: Jake Goldsborough
# url: https://github.com/ducks/discourse-itinerary

enabled_site_setting :itinerary_enabled

register_asset 'stylesheets/itinerary.scss'

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

  # ---- Authoring: persist itinerary fields from the composer ----
  #
  # Discourse's TopicCreator and PostRevisor both read params from the
  # composer. We tell them which extra params to accept and how to
  # save each one to the topic's custom_fields.

  DiscourseItinerary::CUSTOM_FIELDS.each do |field|
    # Allow the composer to send this field through to the server.
    add_permitted_post_create_param(field)

    # Persist edits via PostRevisor (used when the topic is edited).
    PostRevisor.track_topic_field(field.to_sym) do |tc, value|
      tc.record_change(field, tc.topic.custom_fields[field], value)
      tc.topic.custom_fields[field] = value.presence
    end
  end

  # Save on first creation too: when a topic is created, copy any
  # itinerary_* params off the controller's permitted params onto the
  # newly-created topic's custom_fields.
  on(:topic_created) do |topic, opts, user|
    DiscourseItinerary::CUSTOM_FIELDS.each do |field|
      if opts.key?(field.to_sym) || opts.key?(field)
        topic.custom_fields[field] = (opts[field.to_sym] || opts[field]).presence
      end
    end
    topic.save_custom_fields if topic.custom_fields_clean?.is_a?(FalseClass) || topic.custom_fields.any?
  end

  # Expose itinerary fields on the standard topic serializer so the
  # composer can preload them when editing an existing topic.
  DiscourseItinerary::CUSTOM_FIELDS.each do |field|
    add_to_serializer(:topic_view, field.to_sym) do
      object.topic.custom_fields[field]
    end
  end
end
