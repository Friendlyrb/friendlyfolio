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

    sources = response.body.scan(/<source[^>]*>/)
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
end
