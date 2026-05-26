# frozen_string_literal: true

require "rails_helper"

describe DiscourseItinerary::CategoryProvisioner do
  describe ".ensure_category!" do
    # The plugin's after_initialize runs ensure_category! at boot, so by
    # the time these specs execute, an "Itinerary" category and a
    # configured setting already exist. Reset to a clean slate so each
    # example controls its own preconditions.
    before do
      SiteSetting.itinerary_category_id = -1
      Category.where(
        "LOWER(name) = ? OR slug = ?",
        DiscourseItinerary::DEFAULT_CATEGORY_NAME.downcase,
        "itinerary",
      ).destroy_all
    end

    it "creates a new Itinerary category and sets the site setting" do
      expect { described_class.ensure_category! }.to change { Category.count }.by(1)

      category = Category.find_by(name: DiscourseItinerary::DEFAULT_CATEGORY_NAME)
      expect(category).to be_present
      expect(SiteSetting.itinerary_category_id).to eq(category.id)
    end

    it "is a no-op when the site setting already points at a category" do
      existing = Fabricate(:category)
      SiteSetting.itinerary_category_id = existing.id

      expect { described_class.ensure_category! }.not_to change { Category.count }
      expect(SiteSetting.itinerary_category_id).to eq(existing.id)
    end

    it "reprovisions when the configured category has been deleted" do
      orphan = Fabricate(:category)
      SiteSetting.itinerary_category_id = orphan.id
      orphan.destroy!

      expect { described_class.ensure_category! }.to change { Category.count }.by(1)
      expect(SiteSetting.itinerary_category_id).not_to eq(orphan.id)
    end

    it "reuses an existing category with the default name without creating a duplicate" do
      already = Fabricate(:category, name: DiscourseItinerary::DEFAULT_CATEGORY_NAME)

      expect { described_class.ensure_category! }.not_to change { Category.count }
      expect(SiteSetting.itinerary_category_id).to eq(already.id)
    end

    it "matches an existing category by slug regardless of name casing" do
      lower = Fabricate(:category, name: "itinerary", slug: "itinerary")

      expect { described_class.ensure_category! }.not_to change { Category.count }
      expect(SiteSetting.itinerary_category_id).to eq(lower.id)
    end

    it "matches an existing category by case-insensitive name when slug differs" do
      shouty = Fabricate(:category, name: "ITINERARY", slug: "shouty-trips")

      expect { described_class.ensure_category! }.not_to change { Category.count }
      expect(SiteSetting.itinerary_category_id).to eq(shouty.id)
    end

    it "appends the category id to default_categories_muted so new users don't see it on /latest" do
      SiteSetting.default_categories_muted = ""

      described_class.ensure_category!

      ids = SiteSetting.default_categories_muted.split("|")
      expect(ids).to include(SiteSetting.itinerary_category_id.to_s)
    end

    it "does not duplicate the category id in default_categories_muted on repeated provisioning" do
      SiteSetting.default_categories_muted = ""

      described_class.ensure_category!
      first_value = SiteSetting.default_categories_muted

      # Pretend the setting was cleared but the category still exists,
      # so ensure_category! re-finds it and tries to mute again.
      cat_id = SiteSetting.itinerary_category_id
      SiteSetting.itinerary_category_id = -1
      described_class.ensure_category!

      expect(SiteSetting.itinerary_category_id).to eq(cat_id)
      ids = SiteSetting.default_categories_muted.split("|")
      expect(ids.count(cat_id.to_s)).to eq(1)
    end

    it "preserves existing muted categories" do
      other = Fabricate(:category)
      SiteSetting.default_categories_muted = other.id.to_s

      described_class.ensure_category!

      ids = SiteSetting.default_categories_muted.split("|")
      expect(ids).to include(other.id.to_s, SiteSetting.itinerary_category_id.to_s)
    end
  end
end
