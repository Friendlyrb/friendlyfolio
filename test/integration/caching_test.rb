require "test_helper"

class CachingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @gallery = create_gallery
    create_photo(@gallery.sections.first)
  end

  test "a public gallery page is cacheable at the edge" do
    get gallery_path(@gallery)

    assert_match(/public/, response.headers["Cache-Control"])
  end

  # The same URL renders differently for an admin, so caching an admin-rendered
  # response publicly would hand the CDN the unpublished gallery that
  # publication exists to hide.
  test "a page rendered for a signed-in admin is never publicly cacheable" do
    sign_in users(:admin)
    @gallery.update!(published_at: nil)

    get gallery_path(@gallery)

    assert_response :success
    assert_match(/private|no-store/, response.headers["Cache-Control"])
    assert_no_match(/public/, response.headers["Cache-Control"])
  end

  test "an admin previewing an unpublished gallery is warned that its images are public" do
    sign_in users(:admin)
    @gallery.update!(published_at: nil)

    get gallery_path(@gallery)

    assert_match(/Unpublished preview/, response.body)
    assert_match(/permanent\s+public\s+URLs/, response.body)
  end

  test "a published gallery shows no such warning" do
    sign_in users(:admin)

    get gallery_path(@gallery)

    assert_no_match(/Unpublished preview/, response.body)
  end

  # Fastly passes on Set-Cookie and Cloudflare declines to cache it, so a
  # public directive alongside a session cookie buys nothing at all.
  test "a public gallery response sets no session cookie" do
    get gallery_path(@gallery)

    assert_nil response.headers["Set-Cookie"],
               "Set-Cookie on a public page defeats the edge cache it is asking for"
  end

  test "the sign-in page is never publicly cacheable" do
    get new_user_session_path

    assert_no_match(/public/, response.headers["Cache-Control"].to_s)
  end

  # Every image URL is a proxy URL on this host, so the edge cache in front of
  # the app is all that stands between a wall view and Puma. Rails' answer has
  # to be publicly cacheable and cookie-free, or Cloudflare passes it through.
  test "a variant response is cacheable at the edge" do
    get gallery_section_path(@gallery, @gallery.sections.first)
    variant_url = response.body[%r{/rails/active_storage/representations/proxy/[^"\s]+}]
    assert variant_url, "the section page should link its images through the proxy"

    get variant_url

    assert_response :success
    assert_match(/public/, response.headers["Cache-Control"])
    assert_match(/max-age=\d{9,}/, response.headers["Cache-Control"])
    assert_nil response.headers["Set-Cookie"]
  end
end
