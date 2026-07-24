import { module, test } from "qunit";
import { openItineraryComposer } from "discourse/plugins/discourse-itinerary/discourse/lib/open-itinerary-composer";

module("Unit | Lib | open-itinerary-composer", function () {
  test("seeds a new trip after opening the composer", async function (assert) {
    const calls = [];
    const model = {
      setProperties(fields) {
        calls.push(["seed", fields]);
      },
    };
    const composer = {
      model: null,
      async openNewTopic(options) {
        calls.push(["open", options]);
        this.model = model;
      },
    };
    const category = { id: 42 };

    const result = await openItineraryComposer(composer, {
      category,
      itemType: "trip",
    });

    assert.deepEqual(calls, [
      ["open", { category }],
      ["seed", { itinerary_item_type: "trip" }],
    ]);
    assert.strictEqual(result, model);
  });

  test("seeds a parent trip for a new leg", async function (assert) {
    let seededFields;
    const model = {
      setProperties(fields) {
        seededFields = fields;
      },
    };
    const composer = {
      model: null,
      async openNewTopic() {
        this.model = model;
      },
    };

    await openItineraryComposer(composer, { parentTripId: 123 });

    assert.deepEqual(seededFields, {
      itinerary_parent_trip_id: 123,
    });
  });

  test("tolerates the composer declining to open", async function (assert) {
    const composer = {
      model: null,
      async openNewTopic() {},
    };

    const result = await openItineraryComposer(composer, {
      itemType: "trip",
    });

    assert.strictEqual(result, null);
  });
});
