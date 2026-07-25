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

  belongs_to :topic
  belongs_to :created_by, class_name: "User", optional: true

  # 32 url-safe characters (24 random bytes base64-encoded). Long
  # enough that brute-forcing is impractical, short enough that the
  # share URL stays a reasonable length.
  TOKEN_BYTES = 24

  def self.for_topic(topic_id)
    find_by(topic_id: topic_id)
  end

  def self.create_for_topic!(topic_id, created_by:)
    create_or_find_by!(topic_id: topic_id) do |record|
      record.token = generate_token
      record.created_by = created_by
    end
  end

  def self.regenerate_for_topic!(topic_id, created_by:)
    transaction do
      record = lock.find_by(topic_id: topic_id)
      if record
        record.update!(token: generate_token, created_by: created_by)
        record
      else
        create_for_topic!(topic_id, created_by: created_by)
      end
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.generate_token
    SecureRandom.urlsafe_base64(TOKEN_BYTES)
  end
end

# == Schema Information
#
# Table name: itinerary_share_tokens
#
#  id            :bigint           not null, primary key
#  token         :string           not null
#  created_at    :datetime         not null
#  created_by_id :integer
#  topic_id      :integer          not null
#
# Indexes
#
#  index_itinerary_share_tokens_on_created_by_id  (created_by_id)
#  index_itinerary_share_tokens_on_token          (token) UNIQUE
#  index_itinerary_share_tokens_on_topic_id       (topic_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (topic_id => topics.id) ON DELETE => cascade
#
