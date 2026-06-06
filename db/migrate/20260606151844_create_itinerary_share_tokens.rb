# frozen_string_literal: true

class CreateItineraryShareTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :itinerary_share_tokens do |t|
      # The topic this token grants read-only access to. Should be
      # an itinerary trip; we don't enforce that at the DB level
      # (the controller does), so a stray token for a non-trip
      # topic will just 404 on lookup rather than raising here.
      t.integer :topic_id, null: false

      # The token itself - a URL-safe random string. Unique so we
      # can look up by token alone without a topic_id, and indexed
      # so the lookup is O(1).
      t.string :token, null: false

      t.datetime :created_at, null: false
    end

    add_index :itinerary_share_tokens, :token, unique: true
    add_index :itinerary_share_tokens, :topic_id, unique: true
  end
end
