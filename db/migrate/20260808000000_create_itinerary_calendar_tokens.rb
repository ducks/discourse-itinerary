# frozen_string_literal: true

class CreateItineraryCalendarTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :itinerary_calendar_tokens do |t|
      t.integer :user_id, null: false
      t.string :token, null: false
      t.timestamps
    end

    add_index :itinerary_calendar_tokens, :user_id, unique: true
    add_index :itinerary_calendar_tokens, :token, unique: true
    add_foreign_key :itinerary_calendar_tokens, :users, on_delete: :cascade
  end
end
