import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

// /itinerary lists every trip the current user can see.
//
// The model hook returns the response from GET /itinerary/trips,
// which the controller in plugin.rb assembles using TripFinder +
// TripSerializer. The template renders the list.
export default class ItineraryIndexRoute extends DiscourseRoute {
  async model() {
    return await ajax("/itinerary/trips.json");
  }
}
