require "test_helper"

class DownloadsTest < ActionDispatch::IntegrationTest
  setup do
    @gallery = create_gallery
    @section = @gallery.sections.first
    @photo = create_photo(@section)
  end

  test "the original download redirects with an attachment disposition" do
    get download_gallery_section_photo_path(@gallery, @section, @photo)

    assert_response :redirect
    assert_match(/disposition=attachment|attachment/, response.location)
  end

  test "the sharing download serves the JPEG variant, not the original" do
    get download_gallery_section_photo_path(@gallery, @section, @photo, size: "share")

    assert_response :redirect
    assert_no_match(/landscape\.jpg\z/, response.location)
  end

  test "downloading a photo in an unpublished gallery 404s for a visitor" do
    @gallery.update!(published_at: nil)

    get download_gallery_section_photo_path(@gallery, @section, @photo)

      assert_response :not_found
  end

  test "the download control is a link, so it works without JavaScript" do
    get gallery_section_path(@gallery, @section)

    assert_match(/<a[^>]*download/, response.body)
  end
end
