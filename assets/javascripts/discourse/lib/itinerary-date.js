import { shortDate } from "discourse/lib/formatter";

// JavaScript parses a bare YYYY-MM-DD value as midnight UTC. Itinerary dates
// are calendar dates in the traveller's local context, so parsing them as UTC
// can move them to the previous day for users west of Greenwich.
export function itineraryDate(iso) {
  if (!iso) {
    return null;
  }

  const dateOnly = iso.slice(0, 10);
  return new Date(`${dateOnly}T00:00:00`);
}

export function shortItineraryDate(iso) {
  const date = itineraryDate(iso);
  return date ? shortDate(date) : "-";
}
