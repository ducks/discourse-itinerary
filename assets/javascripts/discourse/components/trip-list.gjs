import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import avatar from "discourse/helpers/avatar";
import { shortDate } from "discourse/lib/formatter";

// Renders the /itinerary index: a flat chronological list of trips
// the user can see. The server already sorts by starts_at, so we just
// iterate. Trips without a starts_at (rare; the composer requires it
// for normal items but not for trip topics) sort to the end and
// render with a "no date" placeholder.
export default class TripList extends Component {
  @service composer;
  @service site;
  @service siteSettings;

  formatDate = (iso) => (iso ? shortDate(new Date(iso)) : "-");

  // Opens the standard composer pre-scoped to the itinerary category
  // and seeds the trip item-type so the composer panel hides the
  // item-only fields. The connector reads itinerary_item_type off the
  // composer model.
  @action
  async addTrip() {
    const categoryId = Number(this.siteSettings.itinerary_category_id);
    const category = categoryId > 0 ? this.site.categories.findBy("id", categoryId) : null;

    await this.composer.openNewTopic({ category });
    if (this.composer.model) {
      this.composer.model.set("itinerary_item_type", "trip");
    }
  }

  <template>
    <div class="itinerary-trip-list">
      <div class="itinerary-trip-list__header">
        <h2>Trips</h2>
        <button
          type="button"
          class="btn btn-primary itinerary-trip-list__add"
          {{on "click" this.addTrip}}
        >
          + Add trip
        </button>
      </div>

      {{#if @trips.length}}
        <ul class="itinerary-trips">
          {{#each @trips as |trip|}}
            <li class="itinerary-trips__item">
              <LinkTo @route="itinerary.show" @model={{trip.id}} class="itinerary-trips__link">
                <span class="itinerary-trips__title">{{trip.title}}</span>
                {{#if trip.creator}}
                  <span class="itinerary-trips__creator">
                    {{avatar trip.creator imageSize="small"}}
                    <span class="itinerary-trips__creator-name">{{trip.creator.username}}</span>
                  </span>
                {{/if}}
                <span class="itinerary-trips__dates">
                  {{this.formatDate trip.starts_at}}
                  {{#if trip.ends_at}}
                    to {{this.formatDate trip.ends_at}}
                  {{/if}}
                </span>
                {{#if trip.location}}
                  <span class="itinerary-trips__location">{{trip.location}}</span>
                {{/if}}
              </LinkTo>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class="itinerary-trips__empty">
          No trips yet. Create a topic with type "Trip" to start one.
        </p>
      {{/if}}
    </div>
  </template>
}
