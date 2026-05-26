# frozen_string_literal: true

require "rails_helper"

# Confirms the composer -> server -> custom_fields pipeline works for
# both new topic creation and edits via PostRevisor.
describe "Itinerary authoring" do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:category)

  before { SiteSetting.itinerary_enabled = true }

  it "saves itinerary custom fields on topic creation" do
    creator =
      PostCreator.new(
        user,
        title: "Flight PDX to MAD",
        raw: "Confirmation details inside.",
        category: category.id,
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
    # :topic_with_op also fabricates an OP. PostRevisor needs a real
    # post to revise; bare :topic gives back a Topic with no posts and
    # topic.first_post would be nil.
    topic = Fabricate(:topic_with_op, category: category, user: user)
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

  it "saves trip topics with itinerary_item_type: 'trip'" do
    creator =
      PostCreator.new(
        user,
        title: "Engineering Madrid 2026",
        raw: "Trip workspace.",
        category: category.id,
        itinerary_item_type: "trip",
        itinerary_starts_at: "2026-09-20",
        itinerary_ends_at: "2026-09-25",
        itinerary_location: "Madrid, Spain",
      )
    post = creator.create
    expect(creator.errors.full_messages).to be_empty
    expect(post.topic.custom_fields["itinerary_item_type"]).to eq("trip")
    expect(post.topic.custom_fields["itinerary_location"]).to eq("Madrid, Spain")
  end

  it "saves items with itinerary_parent_trip_id linking back to a trip" do
    creator =
      PostCreator.new(
        user,
        title: "Flight PDX to MAD",
        raw: "Linked to a trip.",
        category: category.id,
        itinerary_item_type: "flight",
        itinerary_parent_trip_id: 42,
      )
    post = creator.create
    expect(creator.errors.full_messages).to be_empty
    # Custom fields registered as :integer come back as Integer on read
    expect(post.topic.custom_fields["itinerary_parent_trip_id"]).to eq(42)
  end

  it "rejects unknown itinerary_item_type values and leaves the field blank" do
    # normalize_field raises Discourse::InvalidParameters from inside
    # the :topic_created event handler. DiscourseEvent catches handler
    # exceptions and logs them rather than re-raising, so the topic
    # itself still gets created with no itinerary_item_type stored.
    creator =
      PostCreator.new(
        user,
        title: "Bogus item type validation",
        raw: "Should not save.",
        category: category.id,
        itinerary_item_type: "spaceflight",
      )
    post = creator.create
    expect(post.topic.custom_fields["itinerary_item_type"]).to be_nil
  end
end
