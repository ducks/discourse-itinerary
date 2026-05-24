// Connector backing the itinerary-fields template. It exposes:
//   - shouldShow:  whether to render the panel for the current composer
//   - composer:    a passthrough handle to the composer model
//   - setX/setY:   actions that write each field back to the composer
//
// The composer model is passed in as `outletArgs.model` per Discourse's
// plugin-outlet contract. We just proxy fields through.

export default {
  shouldRender(args) {
    // Render the panel when the composer is open. A future refinement
    // is to only render when the target category is itinerary-enabled
    // (via a category custom field or a site setting per category).
    return !!args.model;
  },

  setupComponent(args, component) {
    component.composer = args.model;
  },

  actions: {
    setItemType(e) {
      this.composer.set("itinerary_item_type", e.target.value || null);
    },
    setStatus(e) {
      this.composer.set("itinerary_status", e.target.value || null);
    },
    setStartsAt(e) {
      this.composer.set("itinerary_starts_at", e.target.value || null);
    },
    setEndsAt(e) {
      this.composer.set("itinerary_ends_at", e.target.value || null);
    },
    setOrigin(e) {
      this.composer.set("itinerary_origin", e.target.value || null);
    },
    setDestination(e) {
      this.composer.set("itinerary_destination", e.target.value || null);
    },
    setLocation(e) {
      this.composer.set("itinerary_location", e.target.value || null);
    },
    setConfirmationCode(e) {
      this.composer.set("itinerary_confirmation_code", e.target.value || null);
    },
  },
};
