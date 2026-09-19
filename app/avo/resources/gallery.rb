class Avo::Resources::Gallery < Avo::BaseResource
  self.title = :title
  self.icon = "tabler/outline/photo-heart"
  self.includes = [ :cover_photo ]
  self.default_sort_column = :held_on
  self.default_sort_direction = :desc

  # Gallery#to_param is the slug, so every link Avo builds carries a slug where
  # it expects an id. Without this, opening a gallery from the index raises
  # RecordNotFound.
  self.find_record_method = -> {
    next query.where(slug: id).or(query.where(id: id)) if id.is_a?(Array)

    query.find_by(slug: id) || query.find(id)
  }

  # Draft versus published is the one thing worth knowing at a glance, so it
  # rides next to the title on every view rather than only in the form.
  self.discreet_information = [
    { as: :badge, text: -> { record.published_at.present? ? "Published" : "Draft" } }
  ]

  def fields
    field :id, as: :id
    field :title, as: :text, required: true, link_to_record: true
    field :slug, as: :text, required: true,
      help: "The public URL is /&lt;slug&gt;. Changing it breaks every link anyone has already shared."
    field :held_on, as: :date, name: "Held on"
    field :photographer, as: :text,
      help: "Rendered as the credit in the gallery footer. Stripping EXIF removes the photographer's " \
            "copyright tag, so this field is the only credit the site carries."
    field :description, as: :textarea, hide_on: :index

    field :publication, as: :heading, only_on: :forms
    field :published_at, as: :date_time, name: "Published at",
      help: "Empty means nobody but you can see this gallery. Setting a time publishes it -- " \
            "there is no separate publish button, this field <em>is</em> the decision."

    field :cover_photo, as: :belongs_to, name: "Cover photo",
      help: "Falls back to the gallery's first photo when left empty.",
      attach_scope: -> { parent&.persisted? ? query.where(section_id: parent.section_ids) : query }

    # galleries.photos_count is a counter cache on the sections association, so
    # it counts sections, not photos. Count the photos instead of displaying a
    # column whose name promises something it does not hold.
    field "Photos", as: :number, only_on: :display do
      record.photos.count
    end

    field :sections, as: :has_many
  end
end
