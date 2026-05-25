# frozen_string_literal: true

# name: discourse-itinerary
# about: Renders Discourse topics in a category as a chronological travel itinerary.
# version: 0.3.0
# authors: Jake Goldsborough
# url: https://github.com/ducks/discourse-itinerary

enabled_site_setting :itinerary_enabled

register_asset "stylesheets/itinerary.scss"

module ::DiscourseItinerary
  PLUGIN_NAME = "discourse-itinerary"

  # Topic custom fields and their stored types. Names are persisted
  # in Discourse's topic_custom_fields table; types control how
  # Rails parses the stored value on read.
  #
  # Date-shaped values (`itinerary_starts_at`, `itinerary_ends_at`)
  # are stored as ISO-8601 strings rather than DateTime so lexical
  # sorting on the raw column works without a parse step.
  CUSTOM_FIELDS = {
    "itinerary_item_type" => :string,
    "itinerary_parent_trip_id" => :integer,
    "itinerary_starts_at" => :string,
    "itinerary_ends_at" => :string,
    "itinerary_origin" => :string,
    "itinerary_destination" => :string,
    "itinerary_location" => :string,
    "itinerary_confirmation_code" => :string,
    "itinerary_status" => :string,
  }.freeze

  # Allowed values for `itinerary_item_type`. `trip` is the container
  # type; everything else is an item that belongs to a trip via
  # `itinerary_parent_trip_id`.
  VALID_ITEM_TYPES = %w[trip flight train hotel event transfer note].freeze

  # The tag that marks a topic as an itinerary item. Lives in the
  # standard Discourse tag system so existing UI for tag management
  # applies to it.
  ITINERARY_TAG = "itinerary"

  # Coerce a raw incoming value for a known custom field to its
  # storage form. Returns nil for blanks. Raises on values that
  # don't match the field's invariant — currently just the
  # item_type allowlist; other fields are pass-through. Called from
  # both the topic-creation path and PostRevisor.
  def self.normalize_field(field, value)
    presented = value.presence
    return nil if presented.nil?

    case field
    when "itinerary_item_type"
      if VALID_ITEM_TYPES.exclude?(presented)
        raise Discourse::InvalidParameters.new("Unknown itinerary_item_type: #{presented.inspect}")
      end
      presented
    when "itinerary_parent_trip_id"
      presented.to_i
    else
      presented
    end
  end
end

after_initialize do
  # Register the topic custom field types inside after_initialize so
  # Rails has autoloaded the Topic constant by the time we reach for
  # it. The top-level form raises NameError on `Topic` during
  # `rake db:create` and other early-boot tasks.
  DiscourseItinerary::CUSTOM_FIELDS.each do |field, type|
    register_topic_custom_field_type(field, type)
  end

  require_relative "lib/discourse_itinerary/itinerary"
  require_relative "lib/discourse_itinerary/trip_finder"
  require_relative "lib/discourse_itinerary/trip_item_finder"
  require_relative "app/serializers/trip_serializer"
  require_relative "app/serializers/itinerary_item_serializer"
  require_relative "app/controllers/itinerary_controller"

  Discourse::Application.routes.append do
    get "/itinerary/trips" => "itinerary#index",
        :defaults => {
          format: :json,
        },
        :constraints => {
          format: :json,
        }
    get "/itinerary/trips/:id" => "itinerary#show",
        :defaults => {
          format: :json,
        },
        :constraints => {
          format: :json,
          id: /\d+/,
        }
  end

  # ---- Authoring: persist itinerary fields from the composer ----
  #
  # Discourse's TopicCreator and PostRevisor both read params from the
  # composer. We tell them which extra params to accept and how to
  # save each one to the topic's custom_fields.

  DiscourseItinerary::CUSTOM_FIELDS.each_key do |field|
    # Allow the composer to send this field through to the server.
    add_permitted_post_create_param(field)

    # Persist edits via PostRevisor (used when the topic is edited).
    PostRevisor.track_topic_field(field.to_sym) do |tc, value|
      normalized = DiscourseItinerary.normalize_field(field, value)
      tc.record_change(field, tc.topic.custom_fields[field], normalized)
      tc.topic.custom_fields[field] = normalized
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
    provided = DiscourseItinerary::CUSTOM_FIELDS.keys.select { |f| indifferent.key?(f) }
    next if provided.empty?

    provided.each do |field|
      topic.custom_fields[field] = DiscourseItinerary.normalize_field(field, indifferent[field])
    end
    topic.save_custom_fields
  end

  # Expose itinerary fields on the standard topic serializer so the
  # composer can preload them when editing an existing topic.
  DiscourseItinerary::CUSTOM_FIELDS.each_key do |field|
    add_to_serializer(:topic_view, field.to_sym) { object.topic.custom_fields[field] }
  end
end
