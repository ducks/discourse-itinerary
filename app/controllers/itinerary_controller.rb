# frozen_string_literal: true

class ::ItineraryController < ::ApplicationController
  requires_plugin DiscourseItinerary::PLUGIN_NAME

  def show
    category = Category.find_by(slug: params[:category_slug])
    raise Discourse::NotFound unless category

    guardian.ensure_can_see!(category)

    items = DiscourseItinerary::ItineraryFinder.new(
      category: category,
      guardian: guardian
    ).call

    render_json_dump(
      category: {
        id: category.id,
        name: category.name,
        slug: category.slug
      },
      items: items.map { |t|
        ItineraryItemSerializer.new(t, scope: guardian, root: false).as_json
      }
    )
  end
end
