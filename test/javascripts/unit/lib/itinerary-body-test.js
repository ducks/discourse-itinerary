import { module, test } from "qunit";
import { buildItineraryBody } from "discourse/plugins/discourse-itinerary/discourse/lib/itinerary-body";

module("Unit | Lib | itinerary-body", function () {
  test("builds a readable summary without exposing confirmation codes", function (assert) {
    const body = buildItineraryBody({
      itinerary_starts_at: "2026-09-20T14:30",
      itinerary_origin: "PDX",
      itinerary_destination: "MAD",
      itinerary_confirmation_code: "ABC123",
      itinerary_status: "booked",
      itinerary_cost_amount: "842.50",
      itinerary_cost_currency: "USD",
    });

    assert.strictEqual(
      body,
      [
        "- Starts: 2026-09-20T14:30",
        "- Route: PDX -> MAD",
        "- Status: booked",
        "- Cost: 842.50 USD",
      ].join("\n"),
    );
    assert.false(body.includes("ABC123"));
  });
});
