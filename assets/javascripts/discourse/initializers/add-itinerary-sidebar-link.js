import { withPluginApi } from "discourse/lib/plugin-api";

// Adds an "Itinerary" link to the Community section of the sidebar so
// the plugin's canonical entrypoint is discoverable. The category
// itself is muted-by-default for new users (see CategoryProvisioner),
// so without this link there's no obvious way to reach /itinerary.
export default {
  name: "discourse-itinerary-sidebar",

  initialize() {
    withPluginApi((api) => {
      api.addCommunitySectionLink(
        {
          name: "itinerary",
          route: "itinerary.index",
          title: "Itinerary",
          text: "Itinerary",
          icon: "plane",
        },
        true
      );
    });
  },
};
