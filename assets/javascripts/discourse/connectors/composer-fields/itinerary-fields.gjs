import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { eq } from "discourse/truth-helpers";

// Itinerary metadata inputs that appear in the composer when a new
// topic is being authored or the OP is being edited. Mounted into the
// composer-fields plugin outlet.
//
// Each input writes back to the composer model, which then serializes
// the values to the server via the serializeOnCreate / serializeToTopic
// registrations in extend-composer.js.
export default class ItineraryFields extends Component {
  // Itinerary metadata is topic-scoped, so only show the panel when
  // the composer is in a context that affects topic-level metadata:
  // new topics, or edits to the OP. Never for replies, PMs, etc.
  // Per-category gating (only show in itinerary-enabled categories)
  // is a future refinement that probably needs a category custom
  // field to drive it.
  static shouldRender(args) {
    const composer = args.model;
    if (!composer) {
      return false;
    }
    return composer.creatingTopic || composer.editingFirstPost;
  }

  get composer() {
    return this.args.outletArgs.model;
  }

  @action
  setItemType(e) {
    this.composer.set("itinerary_item_type", e.target.value || null);
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
            <option value="" selected={{eq this.composer.itinerary_item_type undefined}}>—</option>
            <option value="flight" selected={{eq this.composer.itinerary_item_type "flight"}}>Flight</option>
            <option value="train" selected={{eq this.composer.itinerary_item_type "train"}}>Train</option>
            <option value="hotel" selected={{eq this.composer.itinerary_item_type "hotel"}}>Hotel</option>
            <option value="event" selected={{eq this.composer.itinerary_item_type "event"}}>Event</option>
            <option value="transfer" selected={{eq this.composer.itinerary_item_type "transfer"}}>Transfer</option>
            <option value="note" selected={{eq this.composer.itinerary_item_type "note"}}>Note</option>
          </select>
        </label>

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
      </div>

      <div class="itinerary-row">
        <label>
          Starts at
          <input
            type="datetime-local"
            value={{this.composer.itinerary_starts_at}}
            {{on "input" this.setStartsAt}}
          />
        </label>

        <label>
          Ends at
          <input
            type="datetime-local"
            value={{this.composer.itinerary_ends_at}}
            {{on "input" this.setEndsAt}}
          />
        </label>
      </div>

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

      <div class="itinerary-row">
        <label>
          Location
          <input
            type="text"
            value={{this.composer.itinerary_location}}
            placeholder="Artrip, Madrid"
            {{on "input" this.setLocation}}
          />
        </label>

        <label>
          Confirmation code
          <input
            type="text"
            value={{this.composer.itinerary_confirmation_code}}
            placeholder="ABC123"
            {{on "input" this.setConfirmationCode}}
          />
        </label>
      </div>
    </details>
  </template>
}
