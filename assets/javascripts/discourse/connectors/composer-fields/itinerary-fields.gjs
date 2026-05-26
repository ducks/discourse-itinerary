import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { and, eq, or } from "discourse/truth-helpers";

// Itinerary metadata inputs that appear in the composer when a new
// topic is being authored or the OP is being edited. Mounted into the
// composer-fields plugin outlet.
//
// Two flavors of topic share this panel:
//   - `trip` items, which are container topics. Date fields are
//     date-only, no origin/destination/status/confirmation/parent.
//   - all other items (flight, hotel, etc), which point at a parent
//     trip via a dropdown. Date fields are datetime, plus the
//     per-type fields that apply.
//
// The conditional rendering pattern is driven by item-type-aware
// getters (`isTrip`, `showsRoute`, `showsLocation`, etc) rather than
// long {{#if (eq ...)}} chains in the template.
export default class ItineraryFields extends Component {
  // Itinerary metadata is topic-scoped, so only mount the panel for
  // composers that affect topic-level metadata: new topics or OP
  // edits. The category gate lives inside the template (see
  // `inItineraryCategory`) so the panel can react to category
  // changes while the composer is open.
  static shouldRender(args) {
    const composer = args.model;
    if (!composer) {
      return false;
    }
    return composer.creatingTopic || composer.editingFirstPost;
  }

  @service siteSettings;

  // Local mirror of the item type so the conditional getters (showsRoute,
  // showsLocation, etc.) re-evaluate when the user picks a new type.
  // Glimmer's autotracking can't follow `composer.set(...)` because
  // composer fields aren't @tracked, so we hold our own copy and push
  // it onto the composer whenever it changes.
  @tracked itemType;
  @tracked availableTrips = [];
  @tracked tripsLoaded = false;
  lastSynthesizedBody = "";

  constructor() {
    super(...arguments);
    this.itemType = this.composer.itinerary_item_type;
    this.loadTrips();
    this.syncBodyClass();
  }

  // Adds a body class when the composer is in the itinerary category
  // AND the user is authoring an item (not a trip). SCSS hides the
  // standard title input under that class since we synthesize the
  // title from itinerary fields. Trips keep the title input visible
  // because the user names a trip meaningfully ("European trip 2026"
  // etc.). The class is removed in willDestroy when the composer
  // closes; we also re-sync on every setItemType so swapping between
  // trip and non-trip toggles the title visibility.
  syncBodyClass() {
    const shouldHide = this.inItineraryCategory && this.itemType && this.itemType !== "trip";
    if (shouldHide) {
      document.body.classList.add("composer-itinerary-item-mode");
    } else {
      document.body.classList.remove("composer-itinerary-item-mode");
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    document.body.classList.remove("composer-itinerary-item-mode");
  }

  get composer() {
    return this.args.outletArgs.model;
  }

  // Whether the composer is in the configured itinerary category.
  // Used to gate the panel contents from the template so it shows up
  // only for itinerary-category topics. Compare as numbers to dodge
  // string-vs-int mismatches between site settings and composer state.
  get inItineraryCategory() {
    const configured = Number(this.siteSettings.itinerary_category_id);
    if (!configured || configured <= 0) {
      return false;
    }
    return Number(this.composer.categoryId) === configured;
  }

  get isTrip() {
    return this.itemType === "trip";
  }

  // Fields the trip type carries that items don't, and vice versa.
  // See the type-x-field matrix in the v0.3 design notes.
  get showsParentTrip() {
    return this.itemType && !this.isTrip;
  }

  get showsStatus() {
    return ["flight", "train", "hotel", "event", "transfer"].includes(this.itemType);
  }

  get showsEndsAt() {
    return this.itemType && this.itemType !== "note";
  }

  get showsRoute() {
    return ["flight", "train", "transfer"].includes(this.itemType);
  }

  get showsLocation() {
    return ["trip", "hotel", "event", "note"].includes(this.itemType);
  }

  // Hotel and event are the types where "name" is meaningfully
  // distinct from "location": a hotel has a brand name + an address,
  // an event has a venue name + an address. Other types either
  // already have a richer identifier (flights have origin/dest) or
  // don't benefit from the distinction (note, transfer).
  get showsName() {
    return ["hotel", "event"].includes(this.itemType);
  }

  get showsConfirmation() {
    return ["flight", "train", "hotel", "event"].includes(this.itemType);
  }

  async loadTrips() {
    // Always scope to the configured itinerary category. We don't
    // rely on the composer's categoryId because at constructor time
    // it can still be unset, and we'd then either bail (showing the
    // "no trips" placeholder forever) or fetch all categories.
    const categoryId = Number(this.siteSettings.itinerary_category_id);
    if (!categoryId || categoryId <= 0) {
      this.tripsLoaded = true;
      return;
    }
    try {
      const response = await ajax("/itinerary/trips.json", {
        data: { category_id: categoryId, created_by_me: true },
      });
      this.availableTrips = response.trips || [];
    } catch {
      // If the request fails (network blip, server error) we just
      // leave the dropdown empty rather than blocking the composer.
      // The placeholder UI handles the empty case identically.
      this.availableTrips = [];
    } finally {
      this.tripsLoaded = true;
    }
  }

  // Synthesizes the topic title from the itinerary fields. Trip
  // topics keep whatever title the user typed (e.g. "European trip
  // 2026"); items get a deterministic title built from their fields,
  // so the user doesn't have to type one. Format:
  //
  //   Flight: PDX -> MAD
  //   Hotel: Madrid Marriott
  //   Event: Symphony
  //   Note
  //
  // For routes that haven't been filled in yet, falls back to the
  // bare type word so the title is never empty.
  synthesizeTitle() {
    const type = this.itemType;
    if (!type || type === "trip") {
      return;
    }

    const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);

    const origin = this.composer.itinerary_origin;
    const destination = this.composer.itinerary_destination;
    const name = this.composer.itinerary_name;
    const location = this.composer.itinerary_location;

    let title = cap(type);
    if (["flight", "train", "transfer"].includes(type) && (origin || destination)) {
      title = `${cap(type)}: ${origin || "?"} -> ${destination || "?"}`;
    } else if (name) {
      title = `${cap(type)}: ${name}`;
    } else if (location) {
      title = `${cap(type)}: ${location}`;
    }

    this.composer.set("title", title);
    this.syncRawBody();
  }

  // Auto-fills the composer's raw body with a rendered summary of all
  // itinerary fields so it (a) easily clears min_first_post_length
  // and (b) gives the user something to skim and add notes to. We
  // only set the body if the user hasn't typed anything custom, so
  // we don't clobber their edits.
  syncRawBody() {
    const current = (this.composer.reply || "").trim();
    if (current && current !== this.lastSynthesizedBody) {
      // User typed their own; don't overwrite.
      return;
    }

    const lines = [];
    const push = (label, value) => {
      if (value) {
        lines.push(`- ${label}: ${value}`);
      }
    };

    push("Starts", this.composer.itinerary_starts_at);
    push("Ends", this.composer.itinerary_ends_at);
    if (this.composer.itinerary_origin || this.composer.itinerary_destination) {
      push(
        "Route",
        [this.composer.itinerary_origin, this.composer.itinerary_destination]
          .filter(Boolean)
          .join(" -> "),
      );
    }
    push("Name", this.composer.itinerary_name);
    push("Location", this.composer.itinerary_location);
    push("Confirmation", this.composer.itinerary_confirmation_code);
    push("Status", this.composer.itinerary_status);

    const body = lines.length ? lines.join("\n") : "";
    this.lastSynthesizedBody = body;
    this.composer.set("reply", body);
  }

  @action
  setItemType(e) {
    const newType = e.target.value || null;
    this.itemType = newType;
    this.composer.set("itinerary_item_type", newType);
    // When switching to/from trip, clear the parent_trip_id so we
    // don't leave stale bookkeeping in the payload (trips don't have
    // a parent trip; items might be re-attached to a different one).
    if (newType === "trip" || newType === null) {
      this.composer.set("itinerary_parent_trip_id", null);
    }
    this.syncBodyClass();
    this.synthesizeTitle();
  }

  @action
  setParentTripId(e) {
    const value = e.target.value;
    this.composer.set("itinerary_parent_trip_id", value ? parseInt(value, 10) : null);
  }

  @action
  setStatus(e) {
    this.composer.set("itinerary_status", e.target.value || null);
    this.syncRawBody();
  }

  // Stored format is "YYYY-MM-DD" (date-only) or "YYYY-MM-DDTHH:MM"
  // (date + time). The composer splits editing into two inputs so the
  // browser doesn't silently drop a half-filled datetime-local value
  // when the user enters a date but no time.
  get startsAtDate() {
    return (this.composer.itinerary_starts_at || "").slice(0, 10);
  }

  get startsAtTime() {
    const v = this.composer.itinerary_starts_at || "";
    return v.includes("T") ? v.split("T")[1].slice(0, 5) : "";
  }

  get endsAtDate() {
    return (this.composer.itinerary_ends_at || "").slice(0, 10);
  }

  get endsAtTime() {
    const v = this.composer.itinerary_ends_at || "";
    return v.includes("T") ? v.split("T")[1].slice(0, 5) : "";
  }

  combineDateTime(date, time) {
    if (!date) {
      return null;
    }
    return time ? `${date}T${time}` : date;
  }

  @action
  setStartsAtDate(e) {
    this.composer.set(
      "itinerary_starts_at",
      this.combineDateTime(e.target.value, this.startsAtTime),
    );
    this.syncRawBody();
  }

  @action
  setStartsAtTime(e) {
    this.composer.set(
      "itinerary_starts_at",
      this.combineDateTime(this.startsAtDate, e.target.value),
    );
    this.syncRawBody();
  }

  @action
  setEndsAtDate(e) {
    this.composer.set(
      "itinerary_ends_at",
      this.combineDateTime(e.target.value, this.endsAtTime),
    );
    this.syncRawBody();
  }

  @action
  setEndsAtTime(e) {
    this.composer.set(
      "itinerary_ends_at",
      this.combineDateTime(this.endsAtDate, e.target.value),
    );
    this.syncRawBody();
  }

  @action
  setOrigin(e) {
    this.composer.set("itinerary_origin", e.target.value || null);
    this.synthesizeTitle();
  }

  @action
  setDestination(e) {
    this.composer.set("itinerary_destination", e.target.value || null);
    this.synthesizeTitle();
  }

  @action
  setName(e) {
    this.composer.set("itinerary_name", e.target.value || null);
    this.synthesizeTitle();
  }

  @action
  setLocation(e) {
    this.composer.set("itinerary_location", e.target.value || null);
    this.synthesizeTitle();
  }

  @action
  setConfirmationCode(e) {
    this.composer.set("itinerary_confirmation_code", e.target.value || null);
    this.syncRawBody();
  }

  <template>
    {{#if this.inItineraryCategory}}
    <details class="itinerary-composer" open>
      <summary>Itinerary item</summary>

      <div class="itinerary-row">
        <label>
          Type
          <select {{on "change" this.setItemType}}>
            <option value="" selected={{eq this.itemType undefined}}>—</option>
            <option value="trip" selected={{eq this.itemType "trip"}}>Trip</option>
            <option value="flight" selected={{eq this.itemType "flight"}}>Flight</option>
            <option value="train" selected={{eq this.itemType "train"}}>Train</option>
            <option value="hotel" selected={{eq this.itemType "hotel"}}>Hotel</option>
            <option value="event" selected={{eq this.itemType "event"}}>Event</option>
            <option value="transfer" selected={{eq this.itemType "transfer"}}>Transfer</option>
            <option value="note" selected={{eq this.itemType "note"}}>Note</option>
          </select>
        </label>

        {{#if this.showsStatus}}
          <label>
            Status
            <select {{on "change" this.setStatus}}>
              <option value="" selected={{eq this.composer.itinerary_status undefined}}>—</option>
              <option value="planned" selected={{eq this.composer.itinerary_status "planned"}}>Planned</option>
              <option value="booked" selected={{eq this.composer.itinerary_status "booked"}}>Booked</option>
              <option value="checked_in" selected={{eq this.composer.itinerary_status "checked_in"}}>Checked in</option>
              <option value="completed" selected={{eq this.composer.itinerary_status "completed"}}>Completed</option>
            </select>
          </label>
        {{/if}}
      </div>

      {{#if this.showsParentTrip}}
        <div class="itinerary-row">
          <label class="itinerary-parent-trip">
            Trip
            {{#if (and this.tripsLoaded (eq this.availableTrips.length 0))}}
              <span class="itinerary-empty-trips">
                No trips yet — create a Trip first
              </span>
            {{else}}
              <select {{on "change" this.setParentTripId}}>
                <option value="" selected={{eq this.composer.itinerary_parent_trip_id undefined}}>—</option>
                {{#each this.availableTrips as |t|}}
                  <option value={{t.id}} selected={{eq this.composer.itinerary_parent_trip_id t.id}}>
                    {{t.title}}
                  </option>
                {{/each}}
              </select>
            {{/if}}
          </label>
        </div>
      {{/if}}

      {{#if this.itemType}}
        <div class="itinerary-row">
          <label>
            Starts at
            <input
              type="date"
              value={{this.startsAtDate}}
              {{on "input" this.setStartsAtDate}}
            />
          </label>

          {{#unless this.isTrip}}
            <label>
              Time
              <input
                type="time"
                value={{this.startsAtTime}}
                {{on "input" this.setStartsAtTime}}
              />
            </label>
          {{/unless}}

          {{#if this.showsEndsAt}}
            <label>
              Ends at
              <input
                type="date"
                value={{this.endsAtDate}}
                {{on "input" this.setEndsAtDate}}
              />
            </label>

            {{#unless this.isTrip}}
              <label>
                Time
                <input
                  type="time"
                  value={{this.endsAtTime}}
                  {{on "input" this.setEndsAtTime}}
                />
              </label>
            {{/unless}}
          {{/if}}
        </div>
      {{/if}}

      {{#if this.showsRoute}}
        <div class="itinerary-row">
          <label>
            Origin
            <input
              type="text"
              value={{this.composer.itinerary_origin}}
              placeholder="PDX"
              {{on "input" this.setOrigin}}
            />
          </label>

          <label>
            Destination
            <input
              type="text"
              value={{this.composer.itinerary_destination}}
              placeholder="MAD"
              {{on "input" this.setDestination}}
            />
          </label>
        </div>
      {{/if}}

      {{#if this.showsName}}
        <div class="itinerary-row">
          <label>
            Name
            <input
              type="text"
              value={{this.composer.itinerary_name}}
              placeholder="Memmo Alfama"
              {{on "input" this.setName}}
            />
          </label>
        </div>
      {{/if}}

      {{#if (or this.showsLocation this.showsConfirmation)}}
        <div class="itinerary-row">
          {{#if this.showsLocation}}
            <label>
              Location
              <input
                type="text"
                value={{this.composer.itinerary_location}}
                placeholder="Artrip, Madrid"
                {{on "input" this.setLocation}}
              />
            </label>
          {{/if}}

          {{#if this.showsConfirmation}}
            <label>
              Confirmation code
              <input
                type="text"
                value={{this.composer.itinerary_confirmation_code}}
                placeholder="ABC123"
                {{on "input" this.setConfirmationCode}}
              />
            </label>
          {{/if}}
        </div>
      {{/if}}
    </details>
    {{/if}}
  </template>
}
