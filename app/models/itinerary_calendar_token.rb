# frozen_string_literal: true

# Bearer credential for a user's subscribable itinerary calendar. There is
# one token per user so requesting the URL repeatedly is idempotent. Rotating
# it immediately revokes the previously issued calendar URL.
class ItineraryCalendarToken < ActiveRecord::Base
  self.table_name = "itinerary_calendar_tokens"

  belongs_to :user

  TOKEN_BYTES = 24

  def self.for_user(user_id)
    find_by(user_id: user_id)
  end

  def self.create_for_user!(user)
    create_or_find_by!(user_id: user.id) { |record| record.token = generate_token }
  end

  def self.regenerate_for_user!(user)
    transaction do
      record = lock.find_by(user_id: user.id)
      if record
        record.update!(token: generate_token)
        record
      else
        create_for_user!(user)
      end
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.generate_token
    SecureRandom.urlsafe_base64(TOKEN_BYTES)
  end
end
