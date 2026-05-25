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
  # category. Items are not returned here; see #show.
  def index
    category = nil
    if params[:category_id].present?
      category = Category.find_by(id: params[:category_id])
      # 404 on both "doesn't exist" and "you can't see it" so we
      # don't leak the existence of categories the caller isn't
      # allowed to know about.
      raise Discourse::NotFound unless category && guardian.can_see?(category)
    end

    trip_topics = DiscourseItinerary::TripFinder.new(guardian: guardian, category: category).call
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
end
