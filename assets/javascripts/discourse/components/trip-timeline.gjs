import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import avatar from "discourse/helpers/avatar";
import { shortItineraryDate } from "../lib/itinerary-date";
import { openItineraryComposer } from "../lib/open-itinerary-composer";

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

  @tracked shareUrl = null;

  // Fetches (or creates) a share token for this trip and exposes
  // the resulting public URL so the template can show it. Repeat
  // clicks reuse the existing token; for rotation use the explicit
  // regenerateShare action.
  @action
  async share() {
    const result = await ajax(`/itinerary/trips/${this.args.trip.id}/share`, {
      type: "POST",
    });
    this.shareUrl = result.url;
  }

  @action
  async regenerateShare() {
    const result = await ajax(`/itinerary/trips/${this.args.trip.id}/share/regenerate`, {
      type: "POST",
    });
    this.shareUrl = result.url;
  }

  @action
  copyShareUrl() {
    if (this.shareUrl) {
      navigator.clipboard?.writeText(this.shareUrl);
    }
  }

  // Opens the composer with the itinerary category and seeds the
  // parent-trip id so a new item lands under this trip. Item-type
  // defaults blank; user picks flight/hotel/etc. in the composer.
  @action
  async addLeg() {
    const categoryId = Number(this.siteSettings.itinerary_category_id);
    const category = categoryId > 0 ? this.site.categories.findBy("id", categoryId) : null;

    await openItineraryComposer(this.composer, {
      category,
      parentTripId: this.args.trip?.id,
    });
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
          label: date ? shortItineraryDate(date) : "Undated",
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

  // Compact "HH:MM ZONE" string. We truncate the IANA name to the
  // city after the final "/" so the timeline doesn't get noisy with
  // "America/Los_Angeles" everywhere — "Los_Angeles" is enough
  // signal for the user reading it.
  formatTimeWithZone = (iso, tz) => {
    const time = this.formatTime(iso);
    if (!time) {
      return "";
    }
    if (!tz) {
      return time;
    }
    const short = tz.split("/").pop().replaceAll("_", " ");
    return `${time} ${short}`;
  };

  // For flights and other cross-tz items, show "08:00 Los Angeles
  // → 11:15 New York" so the traveler sees both ends in local time.
  // For same-tz items, just the start.
  formatItemTime = (item) => {
    const startTz = item.start_timezone;
    const endTz = item.end_timezone;
    const startStr = this.formatTimeWithZone(item.starts_at, startTz);
    if (!item.ends_at || !endTz || endTz === startTz) {
      return startStr;
    }
    return `${startStr} → ${this.formatTimeWithZone(item.ends_at, endTz)}`;
  };

  // "842.50 USD" for display next to an item. Returns null when the
  // item has no cost recorded so the template can skip rendering.
  formatCost = (item) => {
    if (!item.cost_amount || !item.cost_currency) {
      return null;
    }
    const n = Number(item.cost_amount);
    if (Number.isNaN(n)) {
      return `${item.cost_amount} ${item.cost_currency}`;
    }
    // Intl.NumberFormat gives us grouping separators and a sensible
    // number of decimal places per currency. Fall back to the raw
    // string if the runtime doesn't know the currency code (rare).
    try {
      return new Intl.NumberFormat(undefined, {
        style: "currency",
        currency: item.cost_currency,
      }).format(n);
    } catch {
      return `${n.toFixed(2)} ${item.cost_currency}`;
    }
  };

  // Bucket item costs by currency and return a list like
  //   [{ currency: "USD", total: 1240.0, formatted: "$1,240.00" },
  //    { currency: "EUR", total: 450.0,  formatted: "€450.00" }]
  // so the template can render a per-currency totals row at the
  // bottom of the trip. Items without a cost are skipped.
  get totalsByCurrency() {
    const buckets = {};
    for (const item of this.args.items ?? []) {
      if (!item.cost_amount || !item.cost_currency) {
        continue;
      }
      const n = Number(item.cost_amount);
      if (Number.isNaN(n)) {
        continue;
      }
      buckets[item.cost_currency] = (buckets[item.cost_currency] ?? 0) + n;
    }
    return Object.entries(buckets).map(([currency, total]) => {
      let formatted;
      try {
        formatted = new Intl.NumberFormat(undefined, {
          style: "currency",
          currency,
        }).format(total);
      } catch {
        formatted = `${total.toFixed(2)} ${currency}`;
      }
      return { currency, total, formatted };
    });
  }

  <template>
    <div class="itinerary-trip">
      <header class="itinerary-trip__header">
        <div class="itinerary-trip__title-row">
          <h2 class="itinerary-trip__title">{{@trip.title}}</h2>
          <div class="itinerary-trip__actions">
            <a
              class="btn btn-default itinerary-trip__ics"
              href="/itinerary/trips/{{@trip.id}}/ics"
              title="Download as a calendar file you can import into Apple Calendar, Google Calendar, or Outlook."
            >
              Download .ics
            </a>
            <button
              type="button"
              class="btn btn-default itinerary-trip__share"
              title="Get a read-only public URL anyone can view without a Discourse account."
              {{on "click" this.share}}
            >
              Share
            </button>
            <button
              type="button"
              class="btn btn-primary itinerary-trip__add"
              {{on "click" this.addLeg}}
            >
              + Add leg
            </button>
          </div>
        </div>

        {{#if this.shareUrl}}
          <div class="itinerary-trip__share-panel">
            <label>
              <span class="itinerary-trip__share-label">Public read-only link</span>
              <input type="text" readonly value={{this.shareUrl}} />
            </label>
            <button type="button" class="btn btn-default" {{on "click" this.copyShareUrl}}>Copy</button>
            <button type="button" class="btn btn-default" {{on "click" this.regenerateShare}}>Regenerate</button>
          </div>
        {{/if}}
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
                    <span class="itinerary-item__time">{{this.formatItemTime item}}</span>
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
                    {{#let (this.formatCost item) as |cost|}}
                      {{#if cost}}
                        <span class="itinerary-item__cost">{{cost}}</span>
                      {{/if}}
                    {{/let}}
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

      {{#if this.totalsByCurrency.length}}
        <footer class="itinerary-trip__totals">
          <span class="itinerary-trip__totals-label">Trip total</span>
          {{#each this.totalsByCurrency as |bucket|}}
            <span class="itinerary-trip__totals-bucket">{{bucket.formatted}}</span>
          {{/each}}
        </footer>
      {{/if}}
    </div>
  </template>
}
