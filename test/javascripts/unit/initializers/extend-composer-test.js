import { module, test } from "qunit";
import { ITINERARY_FIELDS } from "discourse/plugins/discourse-itinerary/discourse/initializers/extend-composer";

module("Unit | Initializer | extend-composer", function () {
  test("serializes every server-side itinerary field", function (assert) {
    assert.deepEqual(ITINERARY_FIELDS, [
      "itinerary_item_type",
      "itinerary_parent_trip_id",
      "itinerary_starts_at",
      "itinerary_ends_at",
      "itinerary_start_timezone",
      "itinerary_end_timezone",
      "itinerary_origin",
      "itinerary_destination",
      "itinerary_name",
      "itinerary_location",
      "itinerary_confirmation_code",
      "itinerary_status",
      "itinerary_cost_amount",
      "itinerary_cost_currency",
    ]);
  });
});
