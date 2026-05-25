# frozen_string_literal: true

# Wraps a DiscourseItinerary::Itinerary for the JSON routes. Trip-level
# metadata only; items are serialized separately by the trip-show
# controller action.
class TripSerializer < ApplicationSerializer
  attributes :id, :title, :slug, :url, :starts_at, :ends_at, :location, :category_id

  has_one :creator, serializer: BasicUserSerializer, embed: :object

  def id
    object.id
  end

  def title
    object.title
  end

  def slug
    object.slug
  end

  def url
    object.url
  end

  def starts_at
    object.starts_at
  end

  def ends_at
    object.ends_at
  end

  def location
    object.location
  end

  def category_id
    object.category&.id
  end

  def creator
    object.creator
  end

  def include_creator?
    object.creator.present?
  end
end
