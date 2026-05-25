import Component from "@glimmer/component";
import { LinkTo } from "@ember/routing";
import avatar from "discourse/helpers/avatar";
import { shortDate } from "discourse/lib/formatter";

// Renders the /itinerary index: a flat chronological list of trips
// the user can see. The server already sorts by starts_at, so we just
// iterate. Trips without a starts_at (rare; the composer requires it
// for normal items but not for trip topics) sort to the end and
// render with a "no date" placeholder.
export default class TripList extends Component {
  formatDate = (iso) => (iso ? shortDate(new Date(iso)) : "-");

  <template>
    <div class="itinerary-trip-list">
      <h2>Trips</h2>

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
