import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
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
  // Itinerary metadata is topic-scoped, so only show the panel when
  // the composer is in a context that affects topic-level metadata:
  // new topics, or edits to the OP. Never for replies, PMs, etc.
  static shouldRender(args) {
    const composer = args.model;
    if (!composer) {
      return false;
    }
    return composer.creatingTopic || composer.editingFirstPost;
  }

  @tracked availableTrips = [];
  @tracked tripsLoaded = false;

  constructor() {
    super(...arguments);
    this.loadTrips();
  }

  get composer() {
    return this.args.outletArgs.model;
  }

  get itemType() {
    return this.composer.itinerary_item_type;
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

  get showsConfirmation() {
    return ["flight", "train", "hotel", "event"].includes(this.itemType);
  }

  async loadTrips() {
    const categoryId = this.composer.categoryId;
    if (!categoryId) {
      this.tripsLoaded = true;
      return;
    }
    try {
      const response = await ajax("/itinerary/trips.json", {
        data: { category_id: categoryId },
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

  @action
  setItemType(e) {
    const newType = e.target.value || null;
    this.composer.set("itinerary_item_type", newType);
    // When switching to/from trip, clear the parent_trip_id so we
    // don't leave stale bookkeeping in the payload (trips don't have
    // a parent trip; items might be re-attached to a different one).
    if (newType === "trip" || newType === null) {
      this.composer.set("itinerary_parent_trip_id", null);
    }
  }

  @action
  setParentTripId(e) {
    const value = e.target.value;
    this.composer.set("itinerary_parent_trip_id", value ? parseInt(value, 10) : null);
  }

  @action
  setStatus(e) {
    this.composer.set("itinerary_status", e.target.value || null);
  }

  @action
  setStartsAt(e) {
    this.composer.set("itinerary_starts_at", e.target.value || null);
  }

  @action
  setEndsAt(e) {
    this.composer.set("itinerary_ends_at", e.target.value || null);
  }

  @action
  setOrigin(e) {
    this.composer.set("itinerary_origin", e.target.value || null);
  }

  @action
  setDestination(e) {
    this.composer.set("itinerary_destination", e.target.value || null);
  }

  @action
  setLocation(e) {
    this.composer.set("itinerary_location", e.target.value || null);
  }

  @action
  setConfirmationCode(e) {
    this.composer.set("itinerary_confirmation_code", e.target.value || null);
  }

  <template>
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
            {{#if this.isTrip}}
              <input
                type="date"
                value={{this.composer.itinerary_starts_at}}
                {{on "input" this.setStartsAt}}
              />
            {{else}}
              <input
                type="datetime-local"
                value={{this.composer.itinerary_starts_at}}
                {{on "input" this.setStartsAt}}
              />
            {{/if}}
          </label>

          {{#if this.showsEndsAt}}
            <label>
              Ends at
              {{#if this.isTrip}}
                <input
                  type="date"
                  value={{this.composer.itinerary_ends_at}}
                  {{on "input" this.setEndsAt}}
                />
              {{else}}
                <input
                  type="datetime-local"
                  value={{this.composer.itinerary_ends_at}}
                  {{on "input" this.setEndsAt}}
                />
              {{/if}}
            </label>
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
  </template>
}
