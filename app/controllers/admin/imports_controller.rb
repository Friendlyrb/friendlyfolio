module Admin
  # Browser-side bulk import: drop a folder, get a gallery.
  #
  # Files are direct-uploaded straight to storage, so gigabytes never pass
  # through a Rails request. This endpoint only turns an already-uploaded blob
  # into a Photo, one call per file.
  class ImportsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_gallery, only: :create

    def new
      @galleries = Gallery.order(:slug)
    end

    def create
      section = find_or_create_section
      blob = ActiveStorage::Blob.find_signed!(params.require(:signed_id))
      return render(json: { status: "skipped", reason: "already imported" }) if already_imported?(section, blob)

      photo = section.photos.create!(
        position: next_position(section),
        original_filename: params.require(:filename),
        source_digest: blob.checksum
      )
      photo.image.attach(blob)
      photo.reload

      if photo.has_location_data?
        # Caught here rather than in the bake job, so the person who just
        # dropped the folder finds out now instead of discovering a stalled
        # photo later.
        photo.destroy
        render json: { status: "rejected", reason: "GPS location data present" }, status: :unprocessable_content
      else
        render json: { status: "imported", photo_id: photo.id, section: section.slug }
      end
    rescue ActiveRecord::RecordNotUnique
      render json: { status: "skipped", reason: "already imported" }
    end

    private

    def set_gallery
      @gallery = Gallery.find_by!(slug: params.require(:gallery_slug))
    end

    # The dropped folder's own structure decides the sections: a file arriving
    # as "day-1/DSC_0001.jpg" lands in a "day-1" section, created if needed.
    def find_or_create_section
      slug = params[:section_slug].presence&.parameterize || "photos"
      @gallery.sections.find_by(slug: slug) ||
        @gallery.sections.create!(
          slug: slug,
          title: slug.titleize,
          position: (@gallery.sections.maximum(:position) || 0) + 1
        )
    end

    def already_imported?(section, blob)
      section.photos.exists?(source_digest: blob.checksum)
    end

    def next_position(section)
      (section.photos.maximum(:position) || 0) + 1
    end
  end
end
