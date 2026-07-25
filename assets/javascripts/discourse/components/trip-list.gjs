import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { LinkTo } from "@ember/routing";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import dAvatar from "discourse/ui-kit/helpers/d-avatar";
import { i18n } from "discourse-i18n";
import { shortItineraryDate } from "../lib/itinerary-date";
import { openItineraryComposer } from "../lib/open-itinerary-composer";

// Renders the /itinerary index: a flat chronological list of trips
// the user can see. The server already sorts by starts_at, so we just
// iterate. Trips without a starts_at (rare; the composer requires it
// for normal items but not for trip topics) sort to the end and
// render with a "no date" placeholder.
export default class TripList extends Component {
  @service composer;
  @service site;
  @service siteSettings;

  @tracked trips;
  @tracked hasMore;
  @tracked nextPage;
  @tracked loadingMore = false;

  formatDate = shortItineraryDate;

  constructor() {
    super(...arguments);
    this.trips = this.args.trips ?? [];
    this.hasMore = this.args.meta?.has_more ?? false;
    this.nextPage = this.args.meta?.next_page;
  }

  // Opens the standard composer pre-scoped to the itinerary category
  // and seeds the trip item-type so the composer panel hides the
  // item-only fields. The connector reads itinerary_item_type off the
  // composer model.
  @action
  async addTrip() {
    const categoryId = Number(this.siteSettings.itinerary_category_id);
    const category = categoryId > 0 ? this.site.categories.findBy("id", categoryId) : null;

    await openItineraryComposer(this.composer, {
      category,
      itemType: "trip",
    });
  }

  @action
  async loadMore() {
    if (this.loadingMore || !this.hasMore) {
      return;
    }

    this.loadingMore = true;
    try {
      const response = await ajax("/itinerary/trips.json", {
        data: {
          category_id: Number(this.siteSettings.itinerary_category_id),
          page: this.nextPage,
        },
      });
      this.trips = [...this.trips, ...(response.trips ?? [])];
      this.hasMore = response.meta?.has_more ?? false;
      this.nextPage = response.meta?.next_page;
    } finally {
      this.loadingMore = false;
    }
  }

  <template>
    <div class="itinerary-trip-list">
      <div class="itinerary-trip-list__header">
        <h2>{{i18n "itinerary.trips"}}</h2>
        <button
          type="button"
          class="btn btn-primary itinerary-trip-list__add"
          {{on "click" this.addTrip}}
        >
          {{i18n "itinerary.add_trip"}}
        </button>
      </div>

      {{#if this.trips.length}}
        <ul class="itinerary-trips">
          {{#each this.trips as |trip|}}
            <li class="itinerary-trips__item">
              <LinkTo @route="itinerary.show" @model={{trip.id}} class="itinerary-trips__link">
                <span class="itinerary-trips__title">{{trip.title}}</span>
                {{#if trip.creator}}
                  <span class="itinerary-trips__creator">
                    {{dAvatar trip.creator imageSize="small"}}
                    <span class="itinerary-trips__creator-name">{{trip.creator.username}}</span>
                  </span>
                {{/if}}
                <span class="itinerary-trips__dates">
                  {{this.formatDate trip.starts_at}}
                  {{#if trip.ends_at}}
                    {{i18n "itinerary.to"}} {{this.formatDate trip.ends_at}}
                  {{/if}}
                </span>
                {{#if trip.location}}
                  <span class="itinerary-trips__location">{{trip.location}}</span>
                {{/if}}
              </LinkTo>
            </li>
          {{/each}}
        </ul>
        {{#if this.hasMore}}
          <button
            type="button"
            class="btn btn-default itinerary-trip-list__more"
            disabled={{this.loadingMore}}
            {{on "click" this.loadMore}}
          >
            {{i18n "itinerary.load_more"}}
          </button>
        {{/if}}
      {{else}}
        <p class="itinerary-trips__empty">
          {{i18n "itinerary.no_trips"}}
        </p>
      {{/if}}
    </div>
  </template>
}
