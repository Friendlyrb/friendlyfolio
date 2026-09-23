class SectionsController < ApplicationController
  before_action :set_cache_headers
  before_action :set_section

  # Rendered inline for the first section and lazily via a Turbo frame for the
  # rest, so a gallery with 700 photos does not ship them all at once.
  def show
    @page = params[:page].to_i
    @page = 1 if @page < 1
    @photos = paginated_photos
  end

  private

  def set_section
    gallery = admin_signed_in? ? Gallery.all : Gallery.published
    @gallery = gallery.find_by!(slug: params[:gallery_slug])
    @section = @gallery.sections.find_by!(slug: params[:section_slug] || params[:id])
  end

  def paginated_photos
    scope = @section.photos.displayable.with_attached_image
    return scope if scope.count <= Section::PER_PAGE

    scope.offset((@page - 1) * Section::PER_PAGE).limit(Section::PER_PAGE)
  end
end
