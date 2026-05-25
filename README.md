# discourse-itinerary

A Discourse plugin that turns a category of topics into a chronological
travel itinerary, with one trip per topic and its items linked back to it.

Topics carrying the `itinerary` tag and a set of itinerary custom fields are
collected, grouped under their parent trip, sorted by start time, and
returned via plugin routes. Ember pages render the list of trips and the
per-trip timeline grouped by day.

This is an early, narrow tool. It is not a generic notes app, calendar, or
project planner. It just makes a category of Discourse topics readable as a
travel timeline.

## How it works

- **Category** = container for many trips
- **Topic with `itinerary_item_type = trip`** = the trip workspace
- **Other itinerary topics** = items (flight, hotel, train, event, transfer,
  note) that point at their parent trip via `itinerary_parent_trip_id`
- **Tag** `itinerary` = marker that a topic should appear in the timeline
- **Topic custom fields** = structured metadata
- **Plugin routes**: `GET /itinerary/trips` (list trips, optionally
  filtered by `category_id`), `GET /itinerary/trips/:id` (one trip
  with its items, day-grouped on the client)
- **Pages**: `/itinerary` (trip list) and `/itinerary/:trip_id` (timeline)

### Custom fields

Each itinerary topic stores these fields on the standard topic
`custom_fields` table:

| Field                          | Type     | Example                 |
| ------------------------------ | -------- | ----------------------- |
| `itinerary_item_type`          | string   | `flight`                |
| `itinerary_starts_at`          | string   | `2026-09-20T14:30`      |
| `itinerary_ends_at`            | string   | `2026-09-21T09:15`      |
| `itinerary_origin`             | string   | `PDX`                   |
| `itinerary_destination`        | string   | `MAD`                   |
| `itinerary_location`           | string   | `Artrip, Madrid`        |
| `itinerary_confirmation_code`  | string   | `ABC123`                |
| `itinerary_status`             | string   | `booked`                |

Timestamps are stored as ISO-8601 strings; sorting is lexical.

## Status

- **v0.1** — JSON route + Rails-side query
- **v0.2** — composer extension for authoring itinerary topics
- **v0.3** - team-trip data model (one category, many trips), split
  finders, trip + item JSON routes, Ember route and timeline rendering
- **later** — filters, status tracking, icons per type

No ICS export, calendar sync, email parsing, or map view. Not planned for the
near term.

## Site settings

- `itinerary_enabled` (default: true) — kill switch for the plugin

## Requirements

- Discourse with tagging enabled (`SiteSetting.tagging_enabled = true`)
- A tag named `itinerary` (auto-created by the plugin if missing on first use,
  or created manually in Admin → Tags)

## Local development

A `shell.nix` is shipped for the linter/test workflow:

```sh
nix-shell                              # ruby 3.3 + bundler + native deps
bundle install                         # installs gems into ./.gems
bundle exec rubocop                    # lint Ruby
bundle exec stree check $(git ls-files '*.rb') Gemfile
```

To run the specs you need a Discourse checkout — symlink the plugin in and
run rspec from there:

```sh
ln -s $PWD ~/discourse/discourse/plugins/discourse-itinerary
cd ~/discourse/discourse
bin/rspec plugins/discourse-itinerary/spec/
```

## License

MIT.
