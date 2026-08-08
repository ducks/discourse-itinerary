# frozen_string_literal: true

module DiscourseItinerary
  # Formats itinerary items as an iCalendar (RFC 5545) document. A trip title
  # supplies the calendar name for one-trip downloads; aggregate feeds pass an
  # explicit calendar name instead.
  #
  # The output is a single VCALENDAR with one VEVENT per item that has
  # a `starts_at` value. Items without a start time (a bare note, say)
  # are skipped - they have no place on a calendar.
  #
  # When an item has timezones set, the start/end is tagged with a
  # TZID referring to a VTIMEZONE block emitted at the top of the
  # calendar. Stored times are local wall-clock in the named zone,
  # so importing calendars resolve them via their own IANA timezone
  # database keyed on the TZID. Items without a timezone fall back
  # to floating times - the composer prefills timezones for new
  # items but doesn't enforce them on the server, so legacy or
  # API-created items without zones still export cleanly.
  class IcsFormatter
    PRODID = "-//Discourse Itinerary//EN"
    LINE_TERMINATOR = "\r\n"

    def self.call(items:, trip: nil, calendar_name: nil)
      new(items: items, calendar_name: calendar_name || trip&.title).call
    end

    def initialize(items:, calendar_name:)
      @items = items
      @calendar_name = calendar_name
    end

    def call
      lines = []
      lines << "BEGIN:VCALENDAR"
      lines << "VERSION:2.0"
      lines << "PRODID:#{PRODID}"
      lines << "CALSCALE:GREGORIAN"
      lines << "METHOD:PUBLISH"
      lines << "X-WR-CALNAME:#{escape_text(@calendar_name)}"

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

    # Emit concrete timezone transitions covering the itinerary's date
    # range, plus a year on either side. A single "current offset" block
    # is incorrect for trips in another daylight-saving period.
    def vtimezone_lines
      range_start, range_end = timezone_range

      used_timezones.flat_map do |id|
        timezone = TZInfo::Timezone.get(id)
        transitions = timezone.transitions_up_to(range_end, range_start)
        observances =
          if transitions.empty?
            [fixed_offset_observance(timezone, range_start)]
          else
            transitions.map { |transition| transition_observance(transition) }
          end

        [
          "BEGIN:VTIMEZONE",
          "TZID:#{id}",
          "X-LIC-LOCATION:#{id}",
          *observances.flatten,
          "END:VTIMEZONE",
        ]
      rescue TZInfo::InvalidTimezoneIdentifier
        []
      end
    end

    def timezone_range
      years =
        @items.flat_map do |item|
          %w[itinerary_starts_at itinerary_ends_at].filter_map do |field|
            value = cf(item, field).presence
            value.to_s.slice(0, 4).to_i if value
          end
        end
      years = [Time.now.utc.year] if years.empty?
      [Time.utc(years.min - 1, 1, 1), Time.utc(years.max + 2, 1, 1)]
    end

    def transition_observance(transition)
      from = transition.previous_offset
      to = transition.offset
      local_start = transition.at.to_time.utc + from.observed_utc_offset
      kind = to.dst? ? "DAYLIGHT" : "STANDARD"

      [
        "BEGIN:#{kind}",
        "DTSTART:#{local_start.strftime("%Y%m%dT%H%M%S")}",
        "TZOFFSETFROM:#{format_offset(from.observed_utc_offset)}",
        "TZOFFSETTO:#{format_offset(to.observed_utc_offset)}",
        "TZNAME:#{to.abbreviation}",
        "END:#{kind}",
      ]
    end

    def fixed_offset_observance(timezone, range_start)
      period = timezone.period_for_utc(range_start)
      offset = period.observed_utc_offset
      [
        "BEGIN:STANDARD",
        "DTSTART:#{range_start.strftime("%Y%m%dT%H%M%S")}",
        "TZOFFSETFROM:#{format_offset(offset)}",
        "TZOFFSETTO:#{format_offset(offset)}",
        "TZNAME:#{period.abbreviation}",
        "END:STANDARD",
      ]
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
    # use the route ("Flight PDX -> MAD"); hotel/event use the name or
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
      "#{origin} -> #{destination}"
    end

    def location_for(item)
      [cf(item, "itinerary_location"), cf(item, "itinerary_destination")].map(&:presence)
        .compact
        .first
    end

    def description_for(item)
      parts = []
      conf = cf(item, "itinerary_confirmation_code")
      if SiteSetting.itinerary_include_confirmation_codes_in_ics && conf.present?
        parts << "Confirmation: #{conf}"
      end
      status = cf(item, "itinerary_status")
      parts << "Status: #{status}" if status.present?
      parts.join("\n")
    end

    # Build a DTSTART / DTEND property with an optional TZID
    # parameter. When `tz` is present, the time is interpreted as
    # local wall-clock in that zone; when absent we emit a floating
    # time (no TZID parameter) - only used for legacy items written
    # before timezone fields were required.
    def dt_property(name, iso, tz)
      return "#{name};VALUE=DATE:#{iso.delete("-")}" if !iso.include?("T")

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

    # Escape a value for an iCal text field per RFC 5545 3.3.11.
    # Backslash first, then commas, semicolons, and newlines.
    def escape_text(value)
      value.to_s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub(",", "\\,").gsub(";", "\\;")
    end

    # Fold lines without splitting a multibyte UTF-8 character. The
    # continuation space counts toward the 75-octet physical-line limit.
    def fold(line)
      return line if line.bytesize <= 75

      pieces = []
      current = +""
      limit = 75
      line.each_char do |character|
        if current.bytesize + character.bytesize > limit
          pieces << current
          current = +character
          limit = 74
        else
          current << character
        end
      end
      pieces << current unless current.empty?
      pieces.join("#{LINE_TERMINATOR} ")
    end

    def cf(item, key)
      item.custom_fields[key]
    end
  end
end
