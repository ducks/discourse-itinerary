import { withPluginApi } from "discourse/lib/plugin-api";

// Fields the composer needs to send to the server when creating or
// editing an itinerary topic. Mirrors DiscourseItinerary::CUSTOM_FIELDS
// on the Ruby side.
const ITINERARY_FIELDS = [
  "itinerary_item_type",
  "itinerary_starts_at",
  "itinerary_ends_at",
  "itinerary_origin",
  "itinerary_destination",
  "itinerary_location",
  "itinerary_confirmation_code",
  "itinerary_status",
];

export default {
  name: "discourse-itinerary-composer",

  initialize() {
    withPluginApi((api) => {
      // Register every itinerary field on the composer model.
      // serializeOnCreate -> sent on POST /posts (new topic).
      // serializeToTopic  -> sent on PUT /t/<id>  (edit existing topic).
      ITINERARY_FIELDS.forEach((field) => {
        api.serializeOnCreate(field);
        api.serializeToTopic(field, `topic.${field}`);
      });
    });
  },
};
