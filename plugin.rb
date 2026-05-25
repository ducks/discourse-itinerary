# frozen_string_literal: true

# name: discourse-itinerary
# about: Renders Discourse topics in a category as a chronological travel itinerary.
# version: 0.2.0
# authors: Jake Goldsborough
# url: https://github.com/ducks/discourse-itinerary

enabled_site_setting :itinerary_enabled

register_asset "stylesheets/itinerary.scss"

module ::DiscourseItinerary
  PLUGIN_NAME = "discourse-itinerary"

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
  ITINERARY_TAG = "itinerary"
end

after_initialize do
  # Register the topic custom field types inside after_initialize so
  # Rails has autoloaded the Topic constant by the time we reach for
  # it. The top-level form raises NameError on `Topic` during
  # `rake db:create` and other early-boot tasks.
  DiscourseItinerary::CUSTOM_FIELDS.each do |field|
    register_topic_custom_field_type(field, :string)
  end

  require_relative "lib/discourse_itinerary/itinerary_finder"
  require_relative "app/serializers/itinerary_item_serializer"
  require_relative "app/controllers/itinerary_controller"

  Discourse::Application.routes.append do
    get "/itinerary/:category_slug" => "itinerary#show",
        :defaults => {
          format: :json,
        },
        :constraints => {
          format: :json,
        }
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
  # itinerary_* params off the opts hash onto the newly-created topic's
  # custom_fields.
  #
  # `opts` from PostCreator is a plain Hash with symbol keys when
  # callers use kwarg-style, but Email::Receiver passes a different
  # shape; normalize via HashWithIndifferentAccess so we check once.
  # Only save if at least one itinerary field was provided, otherwise
  # we'd write empty custom_fields for every new topic.
  on(:topic_created) do |topic, opts, _user|
    indifferent = opts.with_indifferent_access
    provided = DiscourseItinerary::CUSTOM_FIELDS.select { |f| indifferent.key?(f) }
    next if provided.empty?

    provided.each { |field| topic.custom_fields[field] = indifferent[field].presence }
    topic.save_custom_fields
  end

  # Expose itinerary fields on the standard topic serializer so the
  # composer can preload them when editing an existing topic.
  DiscourseItinerary::CUSTOM_FIELDS.each do |field|
    add_to_serializer(:topic_view, field.to_sym) { object.topic.custom_fields[field] }
  end
end
