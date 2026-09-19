require "test_helper"

class AdminAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:admin)
    @gallery = Gallery.create!(
      slug: "friendlyrb-2024",
      title: "FriendlyRB 2024",
      held_on: Date.new(2024, 5, 16),
      photographer: "Someone With A Camera"
    )
  end

  # The mount sits inside `authenticate :user`, whose constraint is evaluated
  # during routing. A signed-out request never dispatches into Avo's engine at
  # all -- Warden's failure app answers instead -- so the response carries the
  # sign-in page and none of Avo's markup or data.
  test "a signed-out request is turned away before Avo renders anything" do
    [ "/avo", "/avo/resources/galleries", "/avo/resources/galleries/#{@gallery.slug}" ].each do |path|
      get path
      assert_response :redirect, "#{path} should not be served to a signed-out visitor"
      assert_equal "/users/sign_in", URI.parse(response.headers["Location"]).path

      follow_redirect!
      assert_response :success
      assert_no_match(/data-controller="sidebar/, response.body, "#{path} rendered Avo's chrome")
      assert_no_match(/\bAvo\b/, response.body, "#{path} rendered Avo markup")
      assert_no_match "FriendlyRB 2024", response.body, "#{path} leaked admin data"
    end
  end

  test "a signed-in admin reaches the gallery list and the gallery itself" do
    sign_in @admin

    get "/avo/resources/galleries"
    assert_response :success
    assert_match "FriendlyRB 2024", response.body
    assert_match(/data-controller="sidebar/, response.body)

    # Gallery#to_param is the slug, which is what Avo's own links carry. This
    # fails with RecordNotFound unless the resource's find_record_method knows.
    get "/avo/resources/galleries/#{@gallery.slug}"
    assert_response :success
    assert_match "Someone With A Camera", response.body
  end

  test "published_at set from the admin is what makes a gallery public" do
    assert_not @gallery.published?
    assert_not_includes Gallery.published, @gallery

    get "/"
    assert_response :success
    assert_no_match "FriendlyRB 2024", response.body

    sign_in @admin
    patch "/avo/resources/galleries/#{@gallery.slug}",
      params: { gallery: { published_at: "2024-05-20 10:00:00" } }
    assert_response :redirect

    assert @gallery.reload.published?
    assert_includes Gallery.published, @gallery

    sign_out @admin
    get "/"
    assert_response :success
    assert_match "FriendlyRB 2024", response.body
  end

  test "clearing published_at from the admin hides the gallery again" do
    @gallery.update!(published_at: Time.zone.parse("2024-05-20 10:00:00"))

    sign_in @admin
    patch "/avo/resources/galleries/#{@gallery.slug}",
      params: { gallery: { published_at: "" } }
    assert_response :redirect

    assert_nil @gallery.reload.published_at
    assert_not_includes Gallery.published, @gallery

    sign_out @admin
    get "/"
    assert_response :success
    assert_no_match "FriendlyRB 2024", response.body
  end

  test "derived photo columns are shown but never offered as form inputs" do
    section = @gallery.sections.create!(slug: "day-1", title: "Day 1", position: 1)
    photo = create_photo(section, ready: false)

    sign_in @admin

    get "/avo/resources/photos/#{photo.id}"
    assert_response :success
    assert_match photo.width.to_s, response.body
    assert_match "Carries GPS EXIF", response.body
    assert_match "withheld from every public page", response.body

    get "/avo/resources/photos/#{photo.id}/edit"
    assert_response :success
    %w[width height dominant_color derivatives_ready_at source_digest has_location_data].each do |derived|
      assert_no_match(/name="photo\[#{derived}\]"/, response.body,
        "#{derived} is derived from the image; an editable input would claim otherwise")
    end
    assert_match(/name="photo\[position\]"/, response.body)
    assert_match(/name="photo\[image\]"/, response.body)
  end

  # Avo's own index cell for a file field points at the original blob, which
  # proxy mode streams through Puma. The resource substitutes the baked 400px
  # thumbnail, and only once the derivatives exist.
  test "the photo index links thumbnails rather than originals" do
    section = @gallery.sections.create!(slug: "day-1", title: "Day 1", position: 1)
    photo = create_photo(section)

    sign_in @admin
    get "/avo/resources/photos"
    assert_response :success

    assert_match "/representations/", response.body
    assert_no_match(/src="[^"]*\/rails\/active_storage\/blobs\//, response.body,
      "the index should not point an <img> at a multi-megabyte original")
  end

  # A section slug is only unique within its gallery, and Section#to_param is
  # the slug, so Avo's links are ambiguous on their own. Reached from a
  # gallery's sections panel they carry that gallery, which resolves it.
  test "a section slug resolves inside the gallery it was reached from" do
    other = Gallery.create!(slug: "friendlyrb-2023", title: "FriendlyRB 2023", held_on: Date.new(2023, 5, 16))
    @gallery.sections.create!(slug: "day-1", title: "Day 1 in 2024", position: 1)
    other.sections.create!(slug: "day-1", title: "Day 1 in 2023", position: 1)

    sign_in @admin

    get "/avo/resources/sections/day-1",
      params: { via_resource_class: "Avo::Resources::Gallery", via_record_id: other.slug }
    assert_response :success
    assert_match "Day 1 in 2023", response.body
    assert_no_match "Day 1 in 2024", response.body

    get "/avo/resources/sections/day-1",
      params: { via_resource_class: "Avo::Resources::Gallery", via_record_id: @gallery.slug }
    assert_response :success
    assert_match "Day 1 in 2024", response.body
    assert_no_match "Day 1 in 2023", response.body
  end

  # Cheap insurance against a field option that only blows up on one view.
  test "every admin page an editor can reach renders" do
    section = @gallery.sections.create!(slug: "day-1", title: "Day 1", position: 1)
    photo = create_photo(section, fixture: "portrait.jpg")
    @gallery.update!(cover_photo: photo)

    sign_in @admin

    [
      "/avo",
      "/avo/resources/galleries", "/avo/resources/galleries/new",
      "/avo/resources/galleries/#{@gallery.slug}", "/avo/resources/galleries/#{@gallery.slug}/edit",
      "/avo/resources/galleries/#{@gallery.slug}/sections",
      "/avo/resources/sections", "/avo/resources/sections/new",
      "/avo/resources/sections/#{section.slug}", "/avo/resources/sections/#{section.slug}/edit",
      "/avo/resources/sections/#{section.slug}/photos",
      "/avo/resources/photos", "/avo/resources/photos/new",
      "/avo/resources/photos/#{photo.id}", "/avo/resources/photos/#{photo.id}/edit",
      "/avo/resources/users", "/avo/resources/users/#{@admin.id}", "/avo/resources/users/#{@admin.id}/edit"
    ].each do |path|
      get path
      follow_redirect! while response.redirect?
      assert_response :success, "#{path} did not render"
    end
  end
end
