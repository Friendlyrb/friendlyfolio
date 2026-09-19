require "test_helper"

class GalleriesTest < ActionDispatch::IntegrationTest
  test "the index shows a photo count, not a section count" do
    gallery = create_gallery(sections: { "day-1" => "Day 1", "day-2" => "Day 2" })
    gallery.sections.each_with_index { |s, i| 2.times { |n| create_photo(s, position: (i * 2) + n + 1) } }

    assert_equal 4, gallery.reload.photos_count
    assert_equal 2, gallery.sections_count

    get root_path

    assert_match "4 photos", response.body
  end

  test "the index lists published galleries newest first" do
    old = create_gallery(slug: "2023")
    old.update!(held_on: Date.new(2023, 9, 1))
    new = create_gallery(slug: "2025")
    create_gallery(slug: "draft", published: false)

    get root_path

    assert_response :success
    assert_match new.title, response.body
    assert_no_match(/Friendly\.rb draft/, response.body)
    assert_operator response.body.index(new.title), :<, response.body.index(old.title)
  end

  test "a gallery page renders its cover, title and date" do
    gallery = create_gallery
    create_photo(gallery.sections.first)

    get gallery_path(gallery)

    assert_response :success
    assert_match gallery.title, response.body
    assert_match "2025-09-10", response.body
  end

  test "an unpublished gallery 404s for an anonymous visitor" do
    gallery = create_gallery(slug: "secret", published: false)

    get gallery_path(gallery)

    assert_response :not_found
  end

  test "a gallery slug that does not exist 404s rather than raising something else" do
    get "/nope"

    assert_response :not_found
  end

  test "sections render in position order with their descriptions" do
    gallery = create_gallery(sections: { "day-1" => "Day 1", "day-2" => "Day 2" })
    gallery.sections.find_by(slug: "day-1").update!(description: "The first day")
    gallery.sections.each { |s| create_photo(s) }

    get gallery_path(gallery)

    assert_match "The first day", response.body
    assert_operator response.body.index("Day 1"), :<, response.body.index("Day 2")
  end

  test "a single-section gallery renders without section headings" do
    gallery = create_gallery
    create_photo(gallery.sections.first)

    get gallery_path(gallery)

    assert_no_match(/<h2>Day 1<\/h2>/, response.body)
  end

  test "the sign-in route is not swallowed by the gallery slug route" do
    get new_user_session_path

    assert_response :success
  end

  test "sign-up does not exist" do
    get "/users/sign_up"

    assert_response :not_found
  end
end
