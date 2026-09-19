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
end
