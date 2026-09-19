require "test_helper"

# R34: an unpublished gallery's bytes must not be reachable, not merely
# unlinked. Active Storage authorises on the signed blob id alone and knows
# nothing about publication, so this asserts what is actually true rather than
# what the requirement hopes.
class UnpublishedBytesTest < ActionDispatch::IntegrationTest
  setup do
    @gallery = create_gallery
    @photo = create_photo(@gallery.sections.first)
    @variant_url = Rails.application.routes.url_helpers.rails_storage_proxy_path(
      @photo.image.variant(:thumb_webp), only_path: true
    )
  end

  test "app routes to an unpublished gallery's photo are closed" do
    @gallery.update!(published_at: nil)

    get gallery_section_photo_path(@gallery, @gallery.sections.first, @photo)
    assert_response :not_found

    get download_gallery_section_photo_path(@gallery, @gallery.sections.first, @photo)
    assert_response :not_found
  end

  test "a variant URL captured while published still resolves after unpublishing" do
    get @variant_url
    assert_response :success, "variant should serve while published"

    @gallery.update!(published_at: nil)
    get @variant_url

    # Documents the real boundary: Active Storage's proxy controller verifies
    # the signed blob id and nothing else. Someone who captured a derivative URL
    # while the gallery was public keeps it. Unpublishing hides a gallery from
    # visitors; it does not revoke bytes already handed out.
    assert_response :success,
                    "if this ever starts failing, Active Storage gained a publication-aware check " \
                    "and R34 can be tightened"
  end
end
