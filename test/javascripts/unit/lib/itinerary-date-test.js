import { module, test } from "qunit";
import {
  itineraryDate,
  shortItineraryDate,
} from "discourse/plugins/discourse-itinerary/discourse/lib/itinerary-date";

module("Unit | Lib | itinerary-date", function () {
  test("parses a date-only value in local time", function (assert) {
    const date = itineraryDate("2026-09-20");

    assert.strictEqual(date.getFullYear(), 2026);
    assert.strictEqual(date.getMonth(), 8);
    assert.strictEqual(date.getDate(), 20);
    assert.strictEqual(date.getHours(), 0);
  });

  test("uses only the calendar portion of a datetime", function (assert) {
    const date = itineraryDate("2026-09-20T23:30");

    assert.strictEqual(date.getFullYear(), 2026);
    assert.strictEqual(date.getMonth(), 8);
    assert.strictEqual(date.getDate(), 20);
    assert.strictEqual(date.getHours(), 0);
  });

  test("returns an empty-state label for a missing date", function (assert) {
    assert.strictEqual(itineraryDate(null), null);
    assert.strictEqual(shortItineraryDate(null), "-");
  });
});
