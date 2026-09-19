class GalleriesController < ApplicationController
  before_action :set_gallery, only: :show

  def index
    @galleries = visible_galleries.newest_first.includes(cover_photo: { image_attachment: { blob: :variant_records } })
  end

  def show
    @sections = @gallery.sections.includes(:photos)
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
