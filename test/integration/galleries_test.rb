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

  test "a gallery page carries an og:image so shared links unfurl with a picture" do
    gallery = create_gallery(slug: "2022")
    create_photo(gallery.sections.first)

    get gallery_path(gallery)

    og = response.body[/property="og:image" content="([^"]+)"/, 1]
    assert og, "og:image must be set, or every shared link unfurls blank"
    assert_match %r{\Ahttp}, og, "og:image must be absolute for an unfurler"
  end

  test "a photo deep link unfurls as that photo, not the gallery cover" do
    gallery = create_gallery(slug: "2021")
    section = gallery.sections.first
    create_photo(section, position: 1)
    target = create_photo(section, position: 2, fixture: "portrait.jpg")

    get gallery_section_photo_path(gallery, section, target)

    og = response.body[/property="og:image" content="([^"]+)"/, 1]
    assert og

    # The variation is base64 in the path, so decode it rather than matching
    # the variant's Ruby name against an encoded string.
    variation = og.split("/")[-2]
    decoded = Base64.urlsafe_decode64(variation.split("--").first)
    assert_match(/"format":"jpeg"/, decoded,
                 "should unfurl the JPEG tier, which unfurlers can decode")
    assert_match(/portrait/, og, "should unfurl the linked photo, not the gallery cover")
  end

  test "a section page loaded directly is navigable, not a bare wall" do
    gallery = create_gallery(slug: "2020", sections: { "day-1" => "Day 1", "day-2" => "Day 2" })
    section = gallery.sections.find_by(slug: "day-2")
    create_photo(section)

    get gallery_section_path(gallery, section)

    assert_response :success
    # A shared section link has to lead somewhere.
    assert_match(/href="#{Regexp.escape(gallery_path(gallery))}"/, response.body,
                 "a section page must link back to its gallery")
    assert_match(/href="#{Regexp.escape(gallery_section_path(gallery, gallery.sections.first))}"/, response.body,
                 "a section page must link to the gallery's other sections")
    assert_match gallery.title, response.body
    assert_match(/aria-current="page"/, response.body, "the current section should be marked")
  end

  test "the same section requested as a frame stays bare" do
    gallery = create_gallery(slug: "2019")
    section = gallery.sections.first
    create_photo(section)

    get gallery_section_path(gallery, section),
        headers: { "Turbo-Frame" => ActionView::RecordIdentifier.dom_id(section) }

    assert_response :success
    assert_no_match(/class="cover"/, response.body, "a frame response must not repeat the cover")
    assert_no_match(/sections-nav/, response.body, "a frame response must not repeat the nav")
  end
end
