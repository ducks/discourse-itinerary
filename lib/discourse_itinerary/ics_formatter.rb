# frozen_string_literal: true

module DiscourseItinerary
  # Formats a trip and its items as an iCalendar (RFC 5545) document.
  #
  # The output is a single VCALENDAR with one VEVENT per item that has
  # a `starts_at` value. Items without a start time (a bare note, say)
  # are skipped — they have no place on a calendar.
  #
  # When an item has timezones set, the start/end is tagged with a
  # TZID referring to a VTIMEZONE block emitted at the top of the
  # calendar. Stored times are local wall-clock in the named zone,
  # so importing calendars resolve them via their own IANA timezone
  # database keyed on the TZID. Items without a timezone fall back
  # to floating times — the composer prefills timezones for new
  # items but doesn't enforce them on the server, so legacy or
  # API-created items without zones still export cleanly.
  class IcsFormatter
    PRODID = "-//Discourse Itinerary//EN"
    LINE_TERMINATOR = "\r\n"

    def self.call(trip:, items:)
      new(trip: trip, items: items).call
    end

    def initialize(trip:, items:)
      @trip = trip
      @items = items
    end

    def call
      lines = []
      lines << "BEGIN:VCALENDAR"
      lines << "VERSION:2.0"
      lines << "PRODID:#{PRODID}"
      lines << "CALSCALE:GREGORIAN"
      lines << "METHOD:PUBLISH"
      lines << "X-WR-CALNAME:#{escape_text(@trip.title)}"

      vtimezone_lines.each { |l| lines << l }

      now = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")

      @items.each do |item|
        starts_at = cf(item, "itinerary_starts_at")
        next if starts_at.blank?

        ends_at = cf(item, "itinerary_ends_at").presence
        start_tz = cf(item, "itinerary_start_timezone").presence
        end_tz = cf(item, "itinerary_end_timezone").presence
        lines.concat(
          event_lines(
            item,
            starts_at: starts_at,
            ends_at: ends_at,
            start_tz: start_tz,
            end_tz: end_tz,
            dtstamp: now,
          ),
        )
      end

      lines << "END:VCALENDAR"
      lines.map { |l| fold(l) }.join(LINE_TERMINATOR) + LINE_TERMINATOR
    end

    private

    # All distinct IANA zones used by this trip, both start and end.
    # We emit one VTIMEZONE per zone so each TZID parameter in the
    # event blocks resolves against an in-document definition rather
    # than only the importer's database (some strict importers
    # require the in-document definition).
    def used_timezones
      ids = []
      @items.each do |item|
        s = cf(item, "itinerary_start_timezone").presence
        e = cf(item, "itinerary_end_timezone").presence
        ids << s if s
        ids << e if e
      end
      ids.uniq
    end

    # Emit a VTIMEZONE with a single STANDARD component carrying the
    # zone's current offset. We deliberately don't enumerate DST
    # transitions: doing it correctly is involved and importing
    # calendars resolve TZIDs via their own IANA database anyway.
    # The presence of the VTIMEZONE block satisfies strict importers
    # like Outlook; the contents are a hint.
    def vtimezone_lines
      out = []
      used_timezones.each do |id|
        tz = (TZInfo::Timezone.get(id) rescue nil)
        next unless tz
        offset = tz.current_period.utc_offset + tz.current_period.std_offset
        offset_str = format_offset(offset)
        abbrev = tz.current_period.zone_identifier.to_s
        abbrev = id.split("/").last if abbrev.empty?

        out << "BEGIN:VTIMEZONE"
        out << "TZID:#{id}"
        out << "BEGIN:STANDARD"
        out << "DTSTART:19700101T000000"
        out << "TZOFFSETFROM:#{offset_str}"
        out << "TZOFFSETTO:#{offset_str}"
        out << "TZNAME:#{abbrev}"
        out << "END:STANDARD"
        out << "END:VTIMEZONE"
      end
      out
    end

    # Render a UTC offset in seconds as iCal's basic format (+HHMM
    # or -HHMM).
    def format_offset(seconds)
      sign = seconds.negative? ? "-" : "+"
      total = seconds.abs
      hours = total / 3600
      minutes = (total % 3600) / 60
      format("%s%02d%02d", sign, hours, minutes)
    end

    def event_lines(item, starts_at:, ends_at:, start_tz:, end_tz:, dtstamp:)
      out = ["BEGIN:VEVENT"]
      out << "UID:#{uid_for(item)}"
      out << "DTSTAMP:#{dtstamp}"
      out << dt_property("DTSTART", starts_at, start_tz)
      out << dt_property("DTEND", ends_at, end_tz || start_tz) if ends_at
      out << "SUMMARY:#{escape_text(summary_for(item))}"

      loc = location_for(item)
      out << "LOCATION:#{escape_text(loc)}" if loc.present?

      desc = description_for(item)
      out << "DESCRIPTION:#{escape_text(desc)}" if desc.present?

      out << "URL:#{Discourse.base_url}/t/#{item.slug}/#{item.id}"
      out << "END:VEVENT"
      out
    end

    # Stable, globally-unique identifier for a calendar event.
    # Using the topic id + host means re-importing the same .ics
    # updates events rather than duplicating them.
    def uid_for(item)
      host = Discourse.base_url.sub(%r{^https?://}, "")
      "itinerary-#{item.id}@#{host}"
    end

    # Build the SUMMARY line based on item_type. Flight/train/transfer
    # use the route ("Flight PDX → MAD"); hotel/event use the name or
    # location; note falls back to the topic title.
    def summary_for(item)
      type = cf(item, "itinerary_item_type")
      origin = cf(item, "itinerary_origin")
      destination = cf(item, "itinerary_destination")
      name = cf(item, "itinerary_name").presence
      location = cf(item, "itinerary_location").presence

      case type
      when "flight"
        route(origin, destination) ? "Flight #{route(origin, destination)}" : item.title
      when "train"
        route(origin, destination) ? "Train #{route(origin, destination)}" : item.title
      when "transfer"
        route(origin, destination) ? "Transfer #{route(origin, destination)}" : item.title
      when "hotel"
        prefix = name || item.title
        location ? "Hotel: #{prefix} (#{location})" : "Hotel: #{prefix}"
      when "event"
        name || item.title
      else
        item.title
      end
    end

    def route(origin, destination)
      return nil if origin.blank? || destination.blank?
      "#{origin} → #{destination}"
    end

    def location_for(item)
      [cf(item, "itinerary_location"), cf(item, "itinerary_destination")]
        .map(&:presence)
        .compact
        .first
    end

    def description_for(item)
      parts = []
      conf = cf(item, "itinerary_confirmation_code")
      parts << "Confirmation: #{conf}" if conf.present?
      status = cf(item, "itinerary_status")
      parts << "Status: #{status}" if status.present?
      parts.join("\n")
    end

    # Build a DTSTART / DTEND property with an optional TZID
    # parameter. When `tz` is present, the time is interpreted as
    # local wall-clock in that zone; when absent we emit a floating
    # time (no TZID parameter) — only used for legacy items written
    # before timezone fields were required.
    def dt_property(name, iso, tz)
      if tz
        "#{name};TZID=#{tz}:#{ical_datetime(iso)}"
      else
        "#{name}:#{ical_datetime(iso)}"
      end
    end

    # Take an ISO-8601 string ("2026-09-20T14:30") and emit it as
    # iCal's basic format ("20260920T143000"). If the string is a
    # date only ("2026-09-20") we pad to midnight; a strict export
    # would emit VALUE=DATE, but the date-only case only occurs for
    # the trip container which doesn't render its own event.
    def ical_datetime(iso)
      digits = iso.to_s.gsub(/[^0-9]/, "")
      # YYYYMMDDHHMMSS, padding seconds (and minutes if missing).
      padded = digits.ljust(14, "0")[0, 14]
      "#{padded[0, 8]}T#{padded[8, 6]}"
    end

    # Escape a value for an iCal text field per RFC 5545 §3.3.11.
    # Backslash first, then commas, semicolons, and newlines.
    def escape_text(value)
      value
        .to_s
        .gsub("\\", "\\\\\\\\")
        .gsub("\n", "\\n")
        .gsub(",", "\\,")
        .gsub(";", "\\;")
    end

    # Fold lines longer than 75 octets at 75-octet boundaries per
    # RFC 5545 §3.1. Continuation lines start with a single space.
    # Most itinerary lines are short enough to skip folding entirely.
    def fold(line)
      return line if line.bytesize <= 75
      pieces = []
      remaining = line
      while remaining.bytesize > 75
        pieces << remaining.byteslice(0, 75)
        remaining = remaining.byteslice(75..) || ""
      end
      pieces << remaining unless remaining.empty?
      pieces.first + pieces[1..].map { |p| LINE_TERMINATOR + " " + p }.join
    end

    def cf(item, key)
      item.custom_fields[key]
    end
  end
end
