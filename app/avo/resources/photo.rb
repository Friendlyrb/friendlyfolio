class Avo::Resources::Photo < Avo::BaseResource
  self.title = :download_filename
  self.icon = "tabler/outline/photo"
  self.includes = [ :section ]
  self.attachments = [ :image ]
  self.default_sort_column = :position
  self.default_sort_direction = :asc

  def fields
    field :id, as: :id
    field :section, as: :belongs_to, required: true

    # Avo's own index cell for a file field renders the *original* blob, which
    # under proxy mode streams a multi-megabyte JPEG through Puma for every row.
    # Show the baked 400px thumbnail instead, and only once it exists: building
    # a missing variant here would be exactly the synchronous generation the
    # pipeline is designed to avoid.
    field :preview, as: :external_image, only_on: :index, height: 40 do
      next if record.image.blank? || !record.derivatives_ready?

      # `rails_representation_path` is a `direct` route, so it builds a full URL
      # and demands a host unless told otherwise.
      Rails.application.routes.url_helpers.rails_representation_path(
        record.image.variant(:thumb_webp), only_path: true
      )
    end

    field :image, as: :file, accept: "image/*", hide_on: :index,
      help: "One file per photo. Avo Community's file input takes a single file at a time -- " \
            "the 1,900-photo import is <code>bin/rails photos:import</code>, not this form."

    field :position, as: :number,
      help: "Photos render in ascending order within their section."
    field :original_filename, as: :text, name: "Original filename",
      help: "Filled in from the uploaded file when left empty. It is the name a visitor's download gets."

    # Everything below is derived from the image at attach time. It is shown so
    # an admin can see what the pipeline produced, and it is absent from the
    # form because an editable input would imply these can be set by hand.
    field :derivatives_ready_at, as: :date_time, name: "Derivatives ready at", only_on: :display,
      help: "Empty means the nine variants are still baking. Until it is set, the photo is withheld " \
            "from every public page, so a visitor never triggers variant generation mid-request."
    field :width, as: :number, only_on: :display
    field :height, as: :number, only_on: :display
    field :dominant_color, as: :text, name: "Dominant color", only_on: :display, copyable: true,
      help: "Fills the tile before the image arrives."
    field :source_digest, as: :text, name: "Source digest", only_on: :display,
      help: "Deduplicates re-runs of the import task within a section."
  end
end
