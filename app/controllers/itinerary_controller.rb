# frozen_string_literal: true

class ::ItineraryController < ::ApplicationController
  requires_plugin DiscourseItinerary::PLUGIN_NAME

  def show
    category = Category.find_by(slug: params[:category_slug])
    # 404 on both "doesn't exist" and "you can't see it" so the
    # response doesn't leak the existence of categories the caller
    # isn't allowed to know about. Matches the rest of Discourse's
    # private-category handling.
    raise Discourse::NotFound unless category && guardian.can_see?(category)

    items = DiscourseItinerary::ItineraryFinder.new(category: category, guardian: guardian).call

    render_json_dump(
      category: {
        id: category.id,
        name: category.name,
        slug: category.slug,
      },
      items: items.map { |t| ItineraryItemSerializer.new(t, scope: guardian, root: false).as_json },
    )
  end
end
