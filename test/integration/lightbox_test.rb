require "test_helper"

class LightboxTest < ActionDispatch::IntegrationTest
  setup do
    @gallery = create_gallery
    @section = @gallery.sections.first
    @photo = create_photo(@section)
  end

  test "a photo deep link renders the gallery with that photo marked open" do
    get gallery_section_photo_path(@gallery, @section, @photo)

    assert_response :success
    assert_match(/"open":#{@photo.id}/, response.body)
  end

  test "a photo deep link works with no prior session" do
    reset!
    get gallery_section_photo_path(@gallery, @section, @photo)

    assert_response :success
  end

  test "a photo id absent from the section 404s rather than rendering an empty viewer" do
    other = create_photo(create_gallery(slug: "2024").sections.first)

    get gallery_section_photo_path(@gallery, @section, other)

      assert_response :not_found
  end

  test "a photo in an unpublished gallery is not deep-linkable by a visitor" do
    @gallery.update!(published_at: nil)

    get gallery_section_photo_path(@gallery, @section, @photo)

      assert_response :not_found
  end

  test "the dialog carries an accessible name" do
    get gallery_section_path(@gallery, @section)

    assert_match(/<dialog[^>]*aria-label=/, response.body)
  end

  test "tiles are real links, so the viewer works without JavaScript" do
    get gallery_section_path(@gallery, @section)

    assert_match(/<a class="tile"[^>]*href="#{Regexp.escape(gallery_section_photo_path(@gallery, @section, @photo))}"/, response.body)
  end
end
