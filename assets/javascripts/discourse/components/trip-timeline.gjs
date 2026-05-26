import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import avatar from "discourse/helpers/avatar";
import { shortDate } from "discourse/lib/formatter";

// Renders one trip's timeline: a header with trip metadata, then
// items grouped by day. Items are already sorted by starts_at on
// the server side, so the grouping is a straight reduce over the
// pre-sorted list.
//
// Items without a starts_at value never reach here (TripItemFinder
// filters them out), so we can assume every item has a date.
export default class TripTimeline extends Component {
  @service composer;
  @service site;
  @service siteSettings;

  // Opens the composer with the itinerary category and seeds the
  // parent-trip id so a new item lands under this trip. Item-type
  // defaults blank; user picks flight/hotel/etc. in the composer.
  @action
  async addLeg() {
    const categoryId = Number(this.siteSettings.itinerary_category_id);
    const category = categoryId > 0 ? this.site.categories.findBy("id", categoryId) : null;

    await this.composer.openNewTopic({ category });
    if (this.composer.model && this.args.trip?.id) {
      this.composer.model.set("itinerary_parent_trip_id", this.args.trip.id);
    }
  }
  // Returns [{ date: "2026-09-20", label: "Sep 20", items: [...] }, ...]
  // ordered by date ascending. Pre-sorted server-side, so we just
  // partition without re-sorting.
  get itemsByDay() {
    const groups = [];
    let current = null;
    for (const item of this.args.items ?? []) {
      const date = (item.starts_at ?? "").slice(0, 10); // YYYY-MM-DD
      if (!current || current.date !== date) {
        current = {
          date,
          label: date ? shortDate(new Date(date)) : "Undated",
          items: [],
        };
        groups.push(current);
      }
      current.items.push(item);
    }
    return groups;
  }

  formatTime = (iso) => {
    if (!iso) {
      return "";
    }
    // "2026-09-20T14:30" -> "14:30". Cheap slice rather than locale-
    // dependent formatting; the user already sees a date heading.
    const t = iso.split("T")[1];
    return t ? t.slice(0, 5) : "";
  };

  <template>
    <div class="itinerary-trip">
      <header class="itinerary-trip__header">
        <div class="itinerary-trip__title-row">
          <h2 class="itinerary-trip__title">{{@trip.title}}</h2>
          <button
            type="button"
            class="btn btn-primary itinerary-trip__add"
            {{on "click" this.addLeg}}
          >
            + Add leg
          </button>
        </div>
        <div class="itinerary-trip__meta">
          {{#if @trip.creator}}
            <span class="itinerary-trip__creator">
              {{avatar @trip.creator imageSize="small"}}
              <span class="itinerary-trip__creator-name">{{@trip.creator.username}}</span>
            </span>
          {{/if}}
          {{#if @trip.starts_at}}
            <span class="itinerary-trip__dates">
              {{@trip.starts_at}}
              {{#if @trip.ends_at}}
                to {{@trip.ends_at}}
              {{/if}}
            </span>
          {{/if}}
          {{#if @trip.location}}
            <span class="itinerary-trip__location">{{@trip.location}}</span>
          {{/if}}
        </div>
      </header>

      {{#if this.itemsByDay.length}}
        <ol class="itinerary-trip__days">
          {{#each this.itemsByDay as |day|}}
            <li class="itinerary-day">
              <h3 class="itinerary-day__heading">{{day.label}}</h3>
              <ul class="itinerary-day__items">
                {{#each day.items as |item|}}
                  <li class="itinerary-item itinerary-item--{{item.item_type}}">
                    <span class="itinerary-item__time">{{this.formatTime item.starts_at}}</span>
                    <span class="itinerary-item__type">{{item.item_type}}</span>
                    <a class="itinerary-item__title" href={{item.url}}>{{item.title}}</a>
                    {{#if item.origin}}
                      <span class="itinerary-item__route">
                        {{item.origin}} → {{item.destination}}
                      </span>
                    {{else if item.location}}
                      <span class="itinerary-item__location">{{item.location}}</span>
                    {{/if}}
                    {{#if item.status}}
                      <span class="itinerary-item__status itinerary-item__status--{{item.status}}">
                        {{item.status}}
                      </span>
                    {{/if}}
                  </li>
                {{/each}}
              </ul>
            </li>
          {{/each}}
        </ol>
      {{else}}
        <p class="itinerary-trip__empty">
          No items in this trip yet. Add a topic with this trip selected to populate the timeline.
        </p>
      {{/if}}
    </div>
  </template>
}
