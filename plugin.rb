# frozen_string_literal: true

# name: discourse-itinerary
# about: Renders Discourse topics in a category as a chronological travel itinerary.
# version: 0.10.0
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
    # IANA timezone identifiers (e.g. "America/Los_Angeles"). Stored
    # alongside starts_at / ends_at - date/time fields hold local
    # wall-clock times in the named zone, and the calendar export
    # uses these zones to emit VTIMEZONE blocks plus TZID parameters
    # so importing calendars render the correct local times.
    #
    # For most item types both fields hold the same value (a hotel
    # check-in and check-out are in the same city). Flights and
    # cross-tz transfers are the cases where start and end differ.
    "itinerary_start_timezone" => :string,
    "itinerary_end_timezone" => :string,
    "itinerary_origin" => :string,
    "itinerary_destination" => :string,
    "itinerary_name" => :string,
    "itinerary_location" => :string,
    "itinerary_confirmation_code" => :string,
    "itinerary_status" => :string,
    # Cost is stored as two strings: a decimal amount (e.g. "842.50")
    # and a 3-letter ISO 4217 currency code (e.g. "USD"). Amount is
    # a string rather than a numeric type so we don't have to deal
    # with float precision on read-back; the serializer parses it
    # only when rendering trip totals. Both fields are optional - an
    # item without a recorded cost simply omits both.
    "itinerary_cost_amount" => :string,
    "itinerary_cost_currency" => :string,
  }.freeze

  # Allowed values for `itinerary_item_type`. `trip` is the container
  # type; everything else is an item that belongs to a trip via
  # `itinerary_parent_trip_id`.
  VALID_ITEM_TYPES = %w[trip flight train hotel event transfer note].freeze

  # Name used when auto-creating the itinerary category at boot.
  # Admins can rename the category afterwards; the plugin only
  # references it via the `itinerary_category_id` site setting.
  DEFAULT_CATEGORY_NAME = "Itinerary"

  # Returns the configured itinerary category, or nil if the setting
  # is unset / points at a deleted category.
  def self.category
    id = SiteSetting.itinerary_category_id
    return nil if id.blank? || id.to_i <= 0
    Category.find_by(id: id)
  end

  # Coerce a raw incoming value for a known custom field to its
  # storage form. Returns nil for blanks. Raises on values that
  # don't match the field's invariant. Called from both the
  # topic-creation path and PostRevisor.
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
    when "itinerary_start_timezone", "itinerary_end_timezone"
      unless valid_timezone?(presented)
        raise Discourse::InvalidParameters.new("Unknown IANA timezone: #{presented.inspect}")
      end
      presented
    when "itinerary_cost_amount"
      # Accept any decimal-looking value; the serializer parses it
      # later. Negative costs are allowed (a refund could be modeled
      # this way) but commas are rejected to keep the storage form
      # unambiguous - the composer is responsible for stripping
      # locale formatting before sending.
      unless presented =~ /\A-?\d+(\.\d+)?\z/
        raise Discourse::InvalidParameters.new(
                "Invalid itinerary_cost_amount: #{presented.inspect} (expected decimal like '842.50')",
              )
      end
      presented
    when "itinerary_cost_currency"
      # ISO 4217 three-letter codes are uppercase ASCII. We don't
      # validate against a full list - any well-formed three-letter
      # code is accepted, including codes added after this version
      # shipped.
      unless presented =~ /\A[A-Z]{3}\z/
        raise Discourse::InvalidParameters.new(
                "Invalid itinerary_cost_currency: #{presented.inspect} (expected 3 uppercase letters like 'USD')",
              )
      end
      presented
    else
      presented
    end
  end

  # Whether `id` is a recognized IANA timezone identifier. Memoizes
  # the lookup set on first call; TZInfo's identifier list is fixed
  # for a given gem version so the cache lives for the process life.
  def self.valid_timezone?(id)
    @valid_timezones ||= TZInfo::Timezone.all_identifiers.to_set
    @valid_timezones.include?(id)
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

  require_relative "lib/discourse_itinerary/engine"
  require_relative "lib/discourse_itinerary/itinerary"
  require_relative "lib/discourse_itinerary/trip_finder"
  require_relative "lib/discourse_itinerary/trip_item_finder"
  require_relative "lib/discourse_itinerary/itinerary_validator"
  require_relative "lib/discourse_itinerary/category_provisioner"
  require_relative "lib/discourse_itinerary/ics_formatter"
  require_relative "app/models/itinerary_share_token"
  require_relative "app/serializers/trip_serializer"
  require_relative "app/serializers/itinerary_item_serializer"
  require_relative "app/controllers/itinerary_controller"

  # Provision the dedicated itinerary category on first boot. Idempotent:
  # if the setting already points at a category, this is a no-op.
  begin
    DiscourseItinerary::CategoryProvisioner.ensure_category!
  rescue => e
    Rails.logger.warn("discourse-itinerary: failed to provision default category: #{e.message}")
  end

  # Prepend rather than append so our routes win against any
  # Discourse catch-all (the main app has wildcard fallbacks that
  # would otherwise serve the SPA shell for /itinerary/trips/:id/ics
  # before our dedicated export route gets a chance to match).
  Discourse::Application.routes.prepend do
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

    # Calendar download for one trip. The URL deliberately avoids a
    # `.ics` extension because Rails' route system treats dotted
    # endings as format extensions, which fights the page glob below
    # (see rails/rails#20264). Using a slash-separated path takes
    # routing out of the equation entirely; the response sets a
    # `Content-Disposition: attachment; filename=...ics` header so
    # the downloaded file still has the right extension on disk.
    get "/itinerary/trips/:id/ics" => "itinerary#export",
        :defaults => {
          format: :ics,
        },
        :constraints => {
          id: /\d+/,
        }

    # Share-by-link endpoints. POST creates or returns the existing
    # share token; the regenerate variant rotates it. The public
    # GET reads the token out of the URL and renders a read-only
    # view with no session required.
    post "/itinerary/trips/:id/share" => "itinerary#share",
         :defaults => {
           format: :json,
         },
         :constraints => {
           format: :json,
           id: /\d+/,
         }
    post "/itinerary/trips/:id/share/regenerate" => "itinerary#regenerate_share",
         :defaults => {
           format: :json,
         },
         :constraints => {
           format: :json,
           id: /\d+/,
         }
    get "/itinerary/shared/:token" => "itinerary#shared",
        :constraints => {
          token: /[A-Za-z0-9_-]+/,
        }

    # HTML entrypoints for the Ember client routes. Rails matches
    # these URLs and returns Discourse's app shell; Ember then
    # takes over and resolves the path client-side via the plugin's
    # route map. Without these, Rails 404s before the bootstrap HTML
    # reaches the browser.
    get "/itinerary" => "itinerary#page", :constraints => { format: :html }
    get "/itinerary/*path" => "itinerary#page", :constraints => { format: :html }
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
    PostRevisor.track_topic_field(field.to_sym) do |tc, value, fields|
      first_provided_field =
        DiscourseItinerary::CUSTOM_FIELDS.keys.find { |candidate| fields.key?(candidate) }
      if field == first_provided_field
        projected =
          DiscourseItinerary::CUSTOM_FIELDS.keys.to_h do |candidate|
            [
              candidate,
              fields.key?(candidate) ? fields[candidate] : tc.topic.custom_fields[candidate],
            ]
          end
        errors =
          DiscourseItinerary::ItineraryValidator.new(
            fields: projected,
            category_id: tc.topic.category_id,
            guardian: tc.guardian,
          ).call
        errors.each { |error| tc.topic.errors.add(:base, error) }
        tc.check_result(false) if errors.any?
        next if errors.any?
      end

      normalized = DiscourseItinerary.normalize_field(field, value)
      tc.record_change(field, tc.topic.custom_fields[field], normalized)
      tc.topic.custom_fields[field] = normalized
    end
  end

  on(:after_validate_topic) do |topic, topic_creator|
    fields = topic_creator.opts.with_indifferent_access
    errors =
      DiscourseItinerary::ItineraryValidator.new(
        fields: fields,
        category_id: topic.category_id,
        guardian: topic_creator.guardian,
      ).call
    errors.each { |error| topic.errors.add(:base, error) }
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
