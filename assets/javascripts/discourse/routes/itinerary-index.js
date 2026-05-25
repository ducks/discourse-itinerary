import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";

// /itinerary lists every trip in the configured itinerary category.
//
// The model hook hits GET /itinerary/trips, scoped to the
// `itinerary_category_id` site setting if one is configured.
// The controller in plugin.rb assembles results via TripFinder +
// TripSerializer.
export default class ItineraryIndexRoute extends DiscourseRoute {
  @service siteSettings;

  async model() {
    const categoryId = this.siteSettings.itinerary_category_id;
    const data = categoryId && categoryId > 0 ? { category_id: categoryId } : undefined;
    return await ajax("/itinerary/trips.json", { data });
  }
}
