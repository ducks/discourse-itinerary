// Connector backing the itinerary-fields template. It exposes:
//   - composer:    a passthrough handle to the composer model
//   - setX/setY:   actions that write each field back to the composer
//
// The composer model is passed in as `outletArgs.model` per Discourse's
// plugin-outlet contract. We just proxy fields through.

export default {
  // Only render for new topics or first-post edits — never for replies,
  // PMs, or other composer actions. Itinerary metadata is topic-scoped,
  // so editing a reply shouldn't expose it. Per-category gating (only
  // show in itinerary-enabled categories) is a future refinement that
  // probably needs a category custom field to drive it.
  shouldRender(args) {
    const composer = args.model;
    if (!composer) return false;
    return composer.creatingTopic || composer.editingFirstPost;
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
