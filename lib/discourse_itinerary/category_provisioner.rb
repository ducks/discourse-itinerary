# frozen_string_literal: true

module DiscourseItinerary
  # Auto-creates the itinerary category on plugin boot if the
  # `itinerary_category_id` site setting is unset (or points at a
  # deleted category). The setting is the source of truth from then
  # on; renaming or moving the category in the admin UI is fine.
  #
  # Categories created or deliberately selected by this plugin carry
  # an explicit custom-field marker. We never adopt an unrelated
  # category merely because an administrator named it "Itinerary".
  module CategoryProvisioner
    def self.ensure_category!
      existing = DiscourseItinerary.category
      if existing
        mark_managed!(existing)
        return existing
      end

      category = find_managed || create_new!

      SiteSetting.itinerary_category_id = category.id
      mark_managed!(category)
      mute_by_default!(category)
      category
    end

    def self.find_managed
      field =
        CategoryCustomField.find_by(
          name: DiscourseItinerary::MANAGED_CATEGORY_FIELD,
          value: %w[true t 1],
        )
      Category.find_by(id: field&.category_id)
    end

    def self.create_new!
      Category.create!(
        name: available_name,
        user_id: Discourse.system_user.id,
        color: "0088CC",
        text_color: "FFFFFF",
      )
    end

    def self.available_name
      candidate = DEFAULT_CATEGORY_NAME
      suffix = 1
      while Category.where("LOWER(name) = ?", candidate.downcase).exists? ||
              Category.exists?(slug: candidate.parameterize)
        suffix += 1
        candidate = suffix == 2 ? "Travel Itinerary" : "Travel Itinerary #{suffix - 1}"
      end
      candidate
    end

    def self.mark_managed!(category)
      return if category.custom_fields[DiscourseItinerary::MANAGED_CATEGORY_FIELD]

      category.custom_fields[DiscourseItinerary::MANAGED_CATEGORY_FIELD] = true
      category.save_custom_fields
    end

    # Add the category id to default_categories_muted so new users
    # don't see itinerary topics on /latest. Existing users keep their
    # current preference. The list is a pipe-delimited string of ids
    # in Discourse's site-settings layer.
    def self.mute_by_default!(category)
      current = SiteSetting.default_categories_muted.to_s.split("|").reject(&:empty?)
      return if current.include?(category.id.to_s)

      SiteSetting.default_categories_muted = (current + [category.id.to_s]).join("|")
    end
  end
end
