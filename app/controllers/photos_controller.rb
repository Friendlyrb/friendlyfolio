class PhotosController < ApplicationController
  before_action :set_cache_headers
  before_action :set_photo

  # The deep-linked photo view. Renders the gallery with the lightbox open, and
  # on the page that actually contains the photo -- rendering page one for a
  # photo on page two would open the wall with nothing to zoom.
  def show
    @page = @section.page_for(@photo)
    @photos = page_photos
    render "sections/show"
  end

  # Downloads route through here rather than linking an Active Storage URL
  # directly. ActiveStorage::Blobs::RedirectController authorises on the signed
  # blob id alone and knows nothing about whether the gallery is published, so
  # linking it would make every unpublished photo fetchable by anyone holding
  # the URL.
  def download
    redirect_to variant_or_original, allow_other_host: false
  end

  private

  def set_photo
    galleries = admin_signed_in? ? Gallery.all : Gallery.published
    @gallery = galleries.find_by!(slug: params[:gallery_slug])
    @section = @gallery.sections.find_by!(slug: params[:section_slug])
    @photo = @section.photos.displayable.find(params[:id])
  end

  def page_photos
    scope = @section.photos.displayable.with_images
    return scope if scope.count <= Section::PER_PAGE

    scope.offset((@page - 1) * Section::PER_PAGE).limit(Section::PER_PAGE)
  end

  # Redirect mode, not proxy: streaming a multi-megabyte original through the
  # proxy controller pins a Puma thread for the whole transfer.
  def variant_or_original
    if params[:size] == "share"
      rails_storage_redirect_url(
        @photo.image.variant(:share_jpeg).processed,
        disposition: "attachment",
        filename: share_filename
      )
    else
      rails_storage_redirect_url(
        @photo.image,
        disposition: "attachment",
        filename: @photo.download_filename
      )
    end
  end

  def share_filename
    File.basename(@photo.download_filename, ".*") + "-2048.jpg"
  end
end
