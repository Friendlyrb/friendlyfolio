require "test_helper"

class WallTest < ActionDispatch::IntegrationTest
  setup do
    @gallery = create_gallery
    @section = @gallery.sections.first
  end

  test "every tile carries its stored aspect ratio so its space is reserved" do
    create_photo(@section, position: 1)
    create_photo(@section, position: 2, fixture: "portrait.jpg")

    get gallery_section_path(@gallery, @section)

    assert_response :success
    assert_match(/--r: 1\.5/, response.body)
    assert_match(/--r: 0\.6667/, response.body)
  end

  test "every source element carries sizes" do
    create_photo(@section)

    get gallery_section_path(@gallery, @section)

    # Only sources offering a candidate set need sizes. The lightbox's source
    # carries a single image and is populated by JavaScript.
    sources = response.body.scan(/<source[^>]*>/).select { |s| s.include?("srcset=") }
    assert_predicate sources, :any?
    sources.each { |s| assert_match(/sizes=/, s, "a <source> without sizes silently defaults to 100vw") }
  end

  test "images carry explicit width and height" do
    create_photo(@section)

    get gallery_section_path(@gallery, @section)

    assert_match(/<img[^>]*width="3000"[^>]*height="2000"/, response.body)
  end

  test "the first tiles load eagerly and later ones lazily" do
    8.times { |i| create_photo(@section, position: i + 1) }

    get gallery_section_path(@gallery, @section)

    assert_match(/fetchpriority="high"/, response.body)
    assert_match(/loading="lazy"/, response.body)
  end

  test "photos without baked derivatives are not rendered" do
    create_photo(@section, position: 1, ready: false)

    get gallery_section_path(@gallery, @section)

    assert_no_match(/class="tile"/, response.body)
  end

  test "rendering many tiles does not issue a query per tile" do
    20.times { |i| create_photo(@section, position: i + 1) }

    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name].to_s.include?("SCHEMA") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      get gallery_section_path(@gallery, @section)
    end

    assert_operator queries, :<, 20, "wall issued #{queries} queries for 20 tiles"
  end

  # The gallery page loads every section after the first through a turbo-frame.
  # If the section response carries no matching frame, Turbo has nothing to swap
  # in and the section renders "Content missing" -- which is most of the corpus.
  # Asserting on the gallery page's own headings does not catch this, because
  # those render whether or not the frames resolve.
  test "a section response carries a turbo-frame whose id matches the gallery's request" do
    gallery = create_gallery(slug: "2024", sections: { "day-1" => "Day 1", "day-2" => "Day 2" })
    second = gallery.sections.find_by(slug: "day-2")
    create_photo(second)

    get gallery_path(gallery)
    # Attribute order is not guaranteed, so find the frame that requests this
    # section and read its id out of the same tag.
    tag = response.body[/<turbo-frame[^>]*src="[^"]*day-2[^"]*"[^>]*>/]
    assert tag, "gallery page should lazily request the second section in a turbo-frame"
    requested = tag[/id="([^"]+)"/, 1]
    assert requested, "the lazy frame should carry an id"

    # Request it the way the gallery actually does, as a frame.
    get gallery_section_path(gallery, second), headers: { "Turbo-Frame" => requested }

    tag = response.body[/<turbo-frame[^>]*>/]
    assert tag, "section response must carry a turbo-frame"
    assert_equal requested, tag[/id="([^"]+)"/, 1],
                 "section response must carry the frame id the gallery asked for"
  end

  test "the inline first section also carries its frame, so navigating back to it matches" do
    gallery = create_gallery(slug: "2023")
    create_photo(gallery.sections.first)

    get gallery_path(gallery)

    expected = ActionView::RecordIdentifier.dom_id(gallery.sections.first)
    tag = response.body[/<turbo-frame[^>]*>/]
    assert tag, "the inline section should still render inside a frame"
    assert_equal expected, tag[/id="([^"]+)"/, 1]
  end

  # The placeholder is the only thing standing in for the photo while it loads,
  # so it matters that the hash reaches the manifest -- and that a blob nobody
  # has analyzed yet degrades to the dominant colour instead of blowing up.
  test "the lightbox manifest carries a blurhash for an analyzed photo" do
    analyzed = create_photo(@section, position: 1)
    analyzed.image.blob.analyze
    create_photo(@section, position: 2, fixture: "portrait.jpg")

    get gallery_section_path(@gallery, @section)

    assert_response :success
    photos = JSON.parse(response.body[%r{data-lightbox-target="manifest">(.+?)</script>}m, 1])["photos"]
    assert_predicate photos.first["blurhash"], :present?
    assert_nil photos.second["blurhash"]
    assert_predicate photos.second["color"], :present?
  end
end
