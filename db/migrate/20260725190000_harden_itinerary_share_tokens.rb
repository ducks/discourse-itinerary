# frozen_string_literal: true

class HardenItineraryShareTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :itinerary_share_tokens, :created_by_id, :integer
    add_index :itinerary_share_tokens, :created_by_id

    reversible { |direction| direction.up { execute <<~SQL } }
          DELETE FROM itinerary_share_tokens
          WHERE NOT EXISTS (
            SELECT 1
            FROM topics
            WHERE topics.id = itinerary_share_tokens.topic_id
          )
        SQL

    add_foreign_key :itinerary_share_tokens, :topics, column: :topic_id, on_delete: :cascade
    add_foreign_key :itinerary_share_tokens, :users, column: :created_by_id, on_delete: :nullify
  end
end
