class Avo::Resources::Section < Avo::BaseResource
  self.title = :title
  self.icon = "tabler/outline/layout-rows"
  self.includes = [ :gallery ]
  self.default_sort_column = :position
  self.default_sort_direction = :asc

  # Section#to_param is the slug, and a section slug is only unique within its
  # gallery. When the link came from a gallery's sections panel Avo passes that
  # gallery along, which is what makes the slug unambiguous; a slug typed
  # straight into the address bar has no such context and resolves to the first
  # match.
  self.find_record_method = -> {
    next query.where(slug: id).or(query.where(id: id)) if id.is_a?(Array)

    scope = query
    if params && params[:via_resource_class].to_s == "Avo::Resources::Gallery" && params[:via_record_id].present?
      via = params[:via_record_id]
      gallery = Gallery.find_by(slug: via) || Gallery.find_by(id: via)
      scope = scope.where(gallery_id: gallery.id) if gallery
    end

    scope.find_by(slug: id) || query.find_by(slug: id) || query.find(id)
  }

  def fields
    field :id, as: :id
    field :gallery, as: :belongs_to, required: true
    field :title, as: :text, required: true, link_to_record: true
    field :slug, as: :text, required: true,
      help: "Unique within this gallery, and part of the section's public URL."
    field :description, as: :textarea, hide_on: :index
    field :position, as: :number,
      help: "Sections render in ascending order. Lower numbers come first."

    # A counter cache maintained by Photo, so the form has no business offering it.
    field :photos_count, as: :number, name: "Photos", only_on: :display

    field :photos, as: :has_many
  end
end
