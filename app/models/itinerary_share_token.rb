# frozen_string_literal: true

# Read-only share token for a trip. One token per trip (enforced
# by unique index on topic_id) so the "Share" button can return the
# existing token rather than spawning a new one on every click. A
# separate "Regenerate" action deletes-and-recreates when the user
# explicitly wants to invalidate the previous URL.
#
# The token is the only secret on the share URL - there's no auth
# layer behind it. Anyone with the URL can read the trip. Treat it
# like a Google Doc "anyone with the link" share.
class ItineraryShareToken < ActiveRecord::Base
  self.table_name = "itinerary_share_tokens"

  # 32 url-safe characters (24 random bytes base64-encoded). Long
  # enough that brute-forcing is impractical, short enough that the
  # share URL stays a reasonable length.
  TOKEN_BYTES = 24

  def self.for_topic(topic_id)
    find_by(topic_id: topic_id)
  end

  def self.create_for_topic!(topic_id)
    create!(topic_id: topic_id, token: SecureRandom.urlsafe_base64(TOKEN_BYTES))
  end

  def self.regenerate_for_topic!(topic_id)
    where(topic_id: topic_id).delete_all
    create_for_topic!(topic_id)
  end
end
