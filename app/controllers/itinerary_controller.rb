# frozen_string_literal: true

class ::ItineraryController < ::ApplicationController
  requires_plugin DiscourseItinerary::PLUGIN_NAME

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
    category = nil
    if params[:category_id].present?
      category = Category.find_by(id: params[:category_id])
      # 404 on both "doesn't exist" and "you can't see it" so we
      # don't leak the existence of categories the caller isn't
      # allowed to know about.
      raise Discourse::NotFound unless category && guardian.can_see?(category)
    end

    created_by = current_user if params[:created_by_me].to_s == "true" && current_user

    trip_topics =
      DiscourseItinerary::TripFinder.new(
        guardian: guardian,
        category: category,
        created_by: created_by,
      ).call
    trips = trip_topics.map { |t| DiscourseItinerary::Itinerary.new(t, guardian: guardian) }

    render_json_dump(
      trips: trips.map { |trip| TripSerializer.new(trip, scope: guardian, root: false).as_json },
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
    raise Discourse::NotFound unless trip

    ics = DiscourseItinerary::IcsFormatter.call(trip: trip, items: trip.items)

    filename = "#{trip.slug.presence || "trip-#{trip.id}"}.ics"
    response.headers["Content-Disposition"] = "attachment; filename=\"#{filename}\""
    render plain: ics, content_type: "text/calendar; charset=utf-8"
  end
end
