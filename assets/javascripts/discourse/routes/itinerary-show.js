import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

// /itinerary/:trip_id returns one trip plus its items sorted by
// starts_at. The server returns {trip, items}; we pass that through.
//
// 404s (unknown trip, hidden trip, non-trip topic id) bubble up to
// Discourse's default error route.
export default class ItineraryShowRoute extends DiscourseRoute {
  async model(params) {
    return await ajax(`/itinerary/trips/${params.trip_id}.json`);
  }
}
