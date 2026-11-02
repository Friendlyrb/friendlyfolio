class GalleriesController < ApplicationController
  before_action :set_cache_headers
  before_action :set_gallery, only: :show

  # DECK_SIZE photos dealt from every visible gallery for the index's hero. A
  # random pick per render; the CDN holds each for its five minutes.
  DECK_SIZE = 8

  def index
    @galleries = visible_galleries.newest_first.includes(cover_photo: { image_attachment: :blob })
    @deck = Photo.displayable.with_images.includes(section: :gallery)
                 .joins(:section).where(sections: { gallery_id: visible_galleries.select(:id) })
                 .reorder(Arel.sql("RANDOM()")).limit(DECK_SIZE).to_a
  end

  def show
    @sections = @gallery.sections
  end

  private

  def set_gallery
    @gallery = visible_galleries.find_by!(slug: params[:gallery_slug] || params[:id])
  end

  # An unpublished gallery is unreachable for visitors by construction rather
  # than by remembering to filter at each call site. Signed-in admins see it so
  # they can review before publishing.
  def visible_galleries
    admin_signed_in? ? Gallery.all : Gallery.published
  end
end
