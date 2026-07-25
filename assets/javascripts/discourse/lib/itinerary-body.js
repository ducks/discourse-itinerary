// Builds the readable summary used as an itinerary item's initial post body.
// Confirmation codes are deliberately excluded: the topic body is searchable,
// quoted in notifications, and more broadly exposed than structured metadata.
export function buildItineraryBody(item) {
  const lines = [];
  const push = (label, value) => {
    if (value) {
      lines.push(`- ${label}: ${value}`);
    }
  };

  push("Starts", item.itinerary_starts_at);
  push("Ends", item.itinerary_ends_at);
  if (item.itinerary_origin || item.itinerary_destination) {
    push(
      "Route",
      [item.itinerary_origin, item.itinerary_destination].filter(Boolean).join(" -> "),
    );
  }
  push("Name", item.itinerary_name);
  push("Location", item.itinerary_location);
  push("Status", item.itinerary_status);
  if (item.itinerary_cost_amount && item.itinerary_cost_currency) {
    push("Cost", `${item.itinerary_cost_amount} ${item.itinerary_cost_currency}`);
  }

  return lines.join("\n");
}
