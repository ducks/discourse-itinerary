# frozen_string_literal: true

module DiscourseItinerary
  # Auto-creates the itinerary category on plugin boot if the
  # `itinerary_category_id` site setting is unset (or points at a
  # deleted category). The setting is the source of truth from then
  # on; renaming or moving the category in the admin UI is fine.
  #
  # Lookups are slug-first (Discourse normalizes slugs to lowercase
  # ASCII at create time) and fall back to a case-insensitive name
  # match. That way if an admin already has a category called
  # "itinerary" or "ITINERARY", we adopt it instead of creating a
  # duplicate "Itinerary".
  module CategoryProvisioner
    DEFAULT_SLUG = "itinerary"

    def self.ensure_category!
      existing = DiscourseItinerary.category
      return existing if existing

      category = find_existing || create_new!

      SiteSetting.itinerary_category_id = category.id
      category
    end

    def self.find_existing
      Category.find_by(slug: DEFAULT_SLUG) ||
        Category.where("LOWER(name) = ?", DEFAULT_CATEGORY_NAME.downcase).first
    end

    def self.create_new!
      Category.create!(
        name: DEFAULT_CATEGORY_NAME,
        user_id: Discourse.system_user.id,
        color: "0088CC",
        text_color: "FFFFFF",
      )
    end
  end
end
