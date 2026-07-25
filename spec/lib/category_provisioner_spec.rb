# frozen_string_literal: true

require "rails_helper"

describe DiscourseItinerary::CategoryProvisioner do
  describe ".ensure_category!" do
    # The plugin's after_initialize runs ensure_category! at boot, so by
    # the time these specs execute, an "Itinerary" category and a
    # configured setting already exist. Reset to a clean slate so each
    # example controls its own preconditions.
    before do
      # default_categories_muted must be cleared BEFORE we delete the
      # boot-created Itinerary category. Discourse validates that every
      # id in default_categories_muted points at an existing category,
      # so a stale id from a previous test makes the next setting write
      # raise InvalidParameters.
      SiteSetting.default_categories_muted = ""
      SiteSetting.itinerary_category_id = -1
      managed_ids =
        CategoryCustomField.where(name: DiscourseItinerary::MANAGED_CATEGORY_FIELD).pluck(
          :category_id,
        )
      Category.where(id: managed_ids).destroy_all
      Category.where(
        "LOWER(name) = ? OR LOWER(name) LIKE ? OR slug = ?",
        DiscourseItinerary::DEFAULT_CATEGORY_NAME.downcase,
        "travel itinerary%",
        "itinerary",
      ).destroy_all
    end

    it "creates a new Itinerary category and sets the site setting" do
      expect { described_class.ensure_category! }.to change { Category.count }.by(1)

      category = Category.find_by(name: DiscourseItinerary::DEFAULT_CATEGORY_NAME)
      expect(category).to be_present
      expect(SiteSetting.itinerary_category_id).to eq(category.id)
      expect(category.custom_fields[DiscourseItinerary::MANAGED_CATEGORY_FIELD]).to eq(true)
    end

    it "is a no-op when the site setting already points at a category" do
      existing = Fabricate(:category)
      SiteSetting.itinerary_category_id = existing.id

      expect { described_class.ensure_category! }.not_to change { Category.count }
      expect(SiteSetting.itinerary_category_id).to eq(existing.id)
      expect(existing.reload.custom_fields[DiscourseItinerary::MANAGED_CATEGORY_FIELD]).to eq(true)
    end

    it "reprovisions when the configured category has been deleted" do
      orphan = Fabricate(:category)
      SiteSetting.itinerary_category_id = orphan.id
      orphan.destroy!

      expect { described_class.ensure_category! }.to change { Category.count }.by(1)
      expect(SiteSetting.itinerary_category_id).not_to eq(orphan.id)
    end

    it "does not take over an unrelated category with the default name" do
      already = Fabricate(:category, name: DiscourseItinerary::DEFAULT_CATEGORY_NAME)

      expect { described_class.ensure_category! }.to change { Category.count }.by(1)
      expect(SiteSetting.itinerary_category_id).not_to eq(already.id)
      expect(DiscourseItinerary.category.name).to eq("Travel Itinerary")
    end

    it "reuses a previously managed category when the setting is cleared" do
      managed = Fabricate(:category, name: "Team Travel")
      managed.custom_fields[DiscourseItinerary::MANAGED_CATEGORY_FIELD] = true
      managed.save_custom_fields

      expect { described_class.ensure_category! }.not_to change { Category.count }
      expect(SiteSetting.itinerary_category_id).to eq(managed.id)
    end

    it "appends the category id to default_categories_muted so new users don't see it on /latest" do
      SiteSetting.default_categories_muted = ""

      described_class.ensure_category!

      ids = SiteSetting.default_categories_muted.split("|")
      expect(ids).to include(SiteSetting.itinerary_category_id.to_s)
    end

    it "does not duplicate the category id in default_categories_muted on repeated provisioning" do
      described_class.ensure_category!

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
