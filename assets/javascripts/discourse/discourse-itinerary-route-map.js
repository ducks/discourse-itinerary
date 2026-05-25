// Mounts the plugin's frontend routes at /itinerary and
// /itinerary/:trip_id. The Ember router picks this up automatically
// because the filename matches the `<plugin-slug>-route-map.js`
// convention Discourse plugins use.
export default function () {
  this.route("itinerary", { path: "/itinerary" }, function () {
    this.route("show", { path: "/:trip_id" });
  });
}
