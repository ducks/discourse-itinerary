// Opens Discourse's standard new-topic composer and applies itinerary fields
// as one state update before the calling action yields back to rendering.
// Keeping this in one helper prevents shortcut buttons from drifting apart
// and gives the itinerary connector a fully seeded model when it mounts.
export async function openItineraryComposer(
  composer,
  { category, itemType, parentTripId } = {}
) {
  await composer.openNewTopic({ category });

  const fields = {};
  if (itemType) {
    fields.itinerary_item_type = itemType;
  }
  if (parentTripId) {
    fields.itinerary_parent_trip_id = parentTripId;
  }

  composer.model?.setProperties(fields);
  return composer.model;
}
