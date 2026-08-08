# frozen_string_literal: true

class ::ItineraryController < ::ApplicationController
  requires_plugin DiscourseItinerary::PLUGIN_NAME
  prepend_view_path File.expand_path("../views", __dir__)

  TRIPS_PER_PAGE = 50

  # The public share view doesn't require a logged-in session - the
  # whole point is to hand someone outside Discourse a URL that just
  # works. Skip the auth checks Discourse normally enforces.
  skip_before_action :check_xhr, only: %i[export shared calendar]
  skip_before_action :preload_json, only: %i[export shared calendar]
  skip_before_action :redirect_to_login_if_required, only: %i[shared calendar]
  before_action :ensure_logged_in,
                only: %i[
                  share
                  regenerate_share
                  calendar_subscription
                  regenerate_calendar_subscription
                ]

  # GET /itinerary  and  GET /itinerary/:trip_id  (HTML)
  #
  # Serves Discourse's app shell so the Ember client can take over and
  # resolve the path via the plugin's route map. The JSON action below
  # is what actually returns trip data; this action just renders the
  # SPA layout.
  def page
    render "default/empty"
  end

  # GET /itinerary/trips(.json)
  #
  # Lists every trip the user can see, sorted by start date.
  # Optional `category_id` query param scopes the list to one
  # category. Optional `created_by_me=true` narrows to trips the
  # current user created (used by the composer's parent-trip
  # dropdown). Items are not returned here; see #show.
  def index
    category = configured_category!
    if params[:category_id].present? && params[:category_id].to_i != category.id
      raise Discourse::NotFound
    end

    created_by = current_user if params[:created_by_me].to_s == "true" && current_user
    page = [params[:page].to_i, 0].max

    trip_topics =
      DiscourseItinerary::TripFinder.new(
        guardian: guardian,
        category: category,
        created_by: created_by,
        limit: TRIPS_PER_PAGE + 1,
        offset: page * TRIPS_PER_PAGE,
      ).call
    has_more = trip_topics.length > TRIPS_PER_PAGE
    trip_topics = trip_topics.first(TRIPS_PER_PAGE)
    trips = trip_topics.map { |t| DiscourseItinerary::Itinerary.new(t, guardian: guardian) }

    render_json_dump(
      trips: trips.map { |trip| TripSerializer.new(trip, scope: guardian, root: false).as_json },
      meta: {
        has_more: has_more,
        next_page: has_more ? page + 1 : nil,
      },
    )
  end

  # GET /itinerary/trips/:id(.json)
  #
  # Returns one trip plus its items, items sorted by starts_at.
  # 404 if the topic doesn't exist, isn't a trip, or isn't visible.
  def show
    trip = DiscourseItinerary::Itinerary.find(params[:id], guardian: guardian)
    raise Discourse::NotFound unless trip

    render_json_dump(
      trip: TripSerializer.new(trip, scope: guardian, root: false).as_json,
      items:
        trip.items.map { |t| ItineraryItemSerializer.new(t, scope: guardian, root: false).as_json },
    )
  end

  # GET /itinerary/trips/:id.ics
  #
  # Returns a single iCalendar file for the trip, one VEVENT per
  # item with a `starts_at` value. Items without a start time are
  # skipped (notes, for instance).
  #
  # Auth model: requires a logged-in session. Calendar apps that
  # follow subscribe-URL semantics (Apple Calendar, Google Calendar)
  # don't carry browser cookies and so can't subscribe to this URL
  # directly; for the v0.7 use case (download once, double-click to
  # add) that's fine. Per-user subscribe tokens are a follow-up.
  def export
    trip = DiscourseItinerary::Itinerary.find(params[:id], guardian: guardian)
    return head :not_found unless trip

    ics = DiscourseItinerary::IcsFormatter.call(trip: trip, items: trip.items)

    filename = "#{trip.slug.presence || "trip-#{trip.id}"}.ics"
    response.headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
    render plain: ics, content_type: "text/calendar; charset=utf-8"
  end

  # POST /itinerary/calendar-subscription
  #
  # Returns a stable bearer URL that calendar clients can poll without a
  # Discourse session. One token covers every itinerary trip the current user
  # can see; permissions are evaluated again on every feed request.
  def calendar_subscription
    token =
      ItineraryCalendarToken.for_user(current_user.id) ||
        ItineraryCalendarToken.create_for_user!(current_user)

    render_json_dump(url: calendar_url(token.token))
  end

  # POST /itinerary/calendar-subscription/regenerate
  #
  # Rotates the bearer credential, immediately invalidating the old URL.
  def regenerate_calendar_subscription
    token = ItineraryCalendarToken.regenerate_for_user!(current_user)
    render_json_dump(url: calendar_url(token.token))
  end

  # GET /itinerary/calendar/:token/ics
  #
  # Calendar applications periodically fetch this endpoint. The token is the
  # credential, so no browser cookie is required. Generate the document from
  # current data on every request so edits and permission changes flow through
  # to the subscriber on its next refresh.
  def calendar
    token = ItineraryCalendarToken.includes(:user).find_by(token: params[:token])
    user = token&.user
    return head :not_found unless user&.active? && !user.suspended?

    category = DiscourseItinerary.category
    return head :not_found unless category

    user_guardian = Guardian.new(user)
    trips =
      DiscourseItinerary::TripFinder
        .new(guardian: user_guardian, category: category)
        .call
        .map { |topic| DiscourseItinerary::Itinerary.new(topic, guardian: user_guardian) }
    items = trips.flat_map(&:items)
    ics =
      DiscourseItinerary::IcsFormatter.call(
        items: items,
        calendar_name: I18n.t("itinerary.calendar_name"),
      )

    response.headers["Content-Disposition"] = 'inline; filename="itinerary.ics"'
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    render plain: ics, content_type: "text/calendar; charset=utf-8"
  end

  # POST /itinerary/trips/:id/share
  #
  # Returns the existing share token for this trip, creating one if
  # the trip has never been shared. Idempotent on repeat clicks.
  # Requires the caller to be able to edit the trip. Creating a
  # bearer URL can expose a private-category itinerary outside
  # Discourse, so visibility alone is not enough authority.
  def share
    trip = DiscourseItinerary::Itinerary.find(params[:id], guardian: guardian)
    raise Discourse::NotFound unless trip
    guardian.ensure_can_edit!(trip.topic)

    token =
      ItineraryShareToken.for_topic(trip.id) ||
        ItineraryShareToken.create_for_topic!(trip.id, created_by: current_user)

    render_json_dump(token: token.token, url: share_url(token.token))
  end

  # POST /itinerary/trips/:id/share/regenerate
  #
  # Replaces the existing token with a new one, invalidating any
  # previously distributed URL. Same edit-permission bar as `share`.
  def regenerate_share
    trip = DiscourseItinerary::Itinerary.find(params[:id], guardian: guardian)
    raise Discourse::NotFound unless trip
    guardian.ensure_can_edit!(trip.topic)

    token = ItineraryShareToken.regenerate_for_topic!(trip.id, created_by: current_user)
    render_json_dump(token: token.token, url: share_url(token.token))
  end

  # GET /itinerary/shared/:token
  #
  # The public read-only view. No session required - the token in
  # the URL is the only access control. Renders a minimal HTML page
  # (no Ember bootstrap) so the URL loads instantly and works in
  # contexts that don't carry browser cookies (forwarded email,
  # bookmarked link, etc).
  #
  # Hidden vs the authenticated view: cost fields, confirmation
  # codes, the topic creator, and links back into Discourse. The
  # share recipient gets the itinerary, not a back-door into the
  # forum.
  def shared
    token_row = ItineraryShareToken.find_by(token: params[:token])
    return head :not_found unless token_row

    # Use an admin guardian for the topic lookup since the share URL
    # is supposed to work without a session and the trip itself may
    # be in a category the anonymous user can't see. The token *is*
    # the access grant.
    trip =
      DiscourseItinerary::Itinerary.find(
        token_row.topic_id,
        guardian: Guardian.new(Discourse.system_user),
      )
    return head :not_found unless trip

    @trip = trip
    @items = trip.items
    render "shared", layout: "no_ember"
  end

  private

  def share_url(token)
    "#{Discourse.base_url}/itinerary/shared/#{token}"
  end

  def calendar_url(token)
    "#{Discourse.base_url}/itinerary/calendar/#{token}/ics"
  end

  # The site setting is the server-side workspace boundary. Returning 404 for
  # an unset, deleted, or hidden category avoids leaking category existence
  # and keeps API clients from using itinerary fields as a global topic type.
  def configured_category!
    category = DiscourseItinerary.category
    raise Discourse::NotFound unless category && guardian.can_see?(category)

    category
  end
end
