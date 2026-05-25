# frozen_string_literal: true

module DiscourseItinerary
  # Auto-creates the itinerary category on plugin boot if the
  # `itinerary_category_id` site setting is unset (or points at a
  # deleted category). The setting is the source of truth from then
  # on; renaming or moving the category in the admin UI is fine.
  module CategoryProvisioner
    def self.ensure_category!
      existing = DiscourseItinerary.category
      return existing if existing

      system_user = Discourse.system_user

      category =
        Category.find_or_create_by!(name: DEFAULT_CATEGORY_NAME) do |c|
          c.user_id = system_user.id
          c.color = "0088CC"
          c.text_color = "FFFFFF"
        end

      SiteSetting.itinerary_category_id = category.id
      category
    end
  end
end
