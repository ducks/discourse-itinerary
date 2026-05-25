import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import ItineraryFields from "discourse/plugins/discourse-itinerary/discourse/connectors/composer-fields/itinerary-fields";

// Regression coverage for the connector's shouldRender gate. v0.2
// shipped with a {{#if this.shouldShow}} wrapper in the template plus
// no shouldShow assignment in the connector, so the panel never
// actually rendered. The gate now lives on the connector's static
// shouldRender hook (Discourse's outlet contract); these tests lock
// down the four states it has to distinguish so we don't regress to
// "panel never appears" or "panel appears everywhere."
module(
  "Integration | Component | itinerary-fields | shouldRender",
  function (hooks) {
    setupRenderingTest(hooks);

    test("renders when creating a new topic", function (assert) {
      const composer = { creatingTopic: true, editingFirstPost: false };
      assert.true(ItineraryFields.shouldRender({ model: composer }));
    });

    test("renders when editing the first post of a topic", function (assert) {
      const composer = { creatingTopic: false, editingFirstPost: true };
      assert.true(ItineraryFields.shouldRender({ model: composer }));
    });

    test("does not render for a reply", function (assert) {
      const composer = { creatingTopic: false, editingFirstPost: false };
      assert.false(ItineraryFields.shouldRender({ model: composer }));
    });

    test("does not render when no composer model is provided", function (assert) {
      assert.false(ItineraryFields.shouldRender({ model: null }));
      assert.false(ItineraryFields.shouldRender({ model: undefined }));
    });
  }
);
