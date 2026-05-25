# frozen_string_literal: true

require "rails_helper"

# Confirms the composer -> server -> custom_fields pipeline works for
# both new topic creation and edits via PostRevisor.
describe "Itinerary authoring" do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category)
  fab!(:tag) { Fabricate(:tag, name: DiscourseItinerary::ITINERARY_TAG) }

  before do
    SiteSetting.itinerary_enabled = true
    SiteSetting.tagging_enabled = true
    SiteSetting.tag_topic_allowed_groups = Group::AUTO_GROUPS[:everyone]
  end

  it "saves itinerary custom fields on topic creation" do
    creator =
      PostCreator.new(
        user,
        title: "Flight PDX to MAD",
        raw: "Confirmation details inside.",
        category: category.id,
        tags: [DiscourseItinerary::ITINERARY_TAG],
        itinerary_item_type: "flight",
        itinerary_starts_at: "2026-09-20T14:30",
        itinerary_origin: "PDX",
        itinerary_destination: "MAD",
        itinerary_status: "booked",
      )
    post = creator.create
    expect(creator.errors.full_messages).to be_empty
    topic = post.topic

    expect(topic.custom_fields["itinerary_item_type"]).to eq("flight")
    expect(topic.custom_fields["itinerary_starts_at"]).to eq("2026-09-20T14:30")
    expect(topic.custom_fields["itinerary_origin"]).to eq("PDX")
    expect(topic.custom_fields["itinerary_destination"]).to eq("MAD")
    expect(topic.custom_fields["itinerary_status"]).to eq("booked")
  end

  it "updates itinerary custom fields via PostRevisor" do
    topic = Fabricate(:topic, category: category, tags: [tag], user: user)
    topic.custom_fields["itinerary_status"] = "planned"
    topic.custom_fields["itinerary_item_type"] = "flight"
    topic.save_custom_fields

    revisor = PostRevisor.new(topic.first_post, topic)
    revisor.revise!(user, { itinerary_status: "booked", itinerary_confirmation_code: "ABC123" })

    topic.reload
    expect(topic.custom_fields["itinerary_status"]).to eq("booked")
    expect(topic.custom_fields["itinerary_confirmation_code"]).to eq("ABC123")
    expect(topic.custom_fields["itinerary_item_type"]).to eq("flight")
  end
end
