require "test_helper"

class SeoTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def head_value(pattern) = response.body[pattern, 1]

  def json_ld
    JSON.parse(response.body[%r{<script type="application/ld\+json">(.*?)</script>}m, 1])
  end

  test "every public page has a description, canonical, robots and a full social card" do
    gallery = create_gallery
    section = gallery.sections.first
    photo = create_photo(section)

    [ root_path, gallery_path(gallery), gallery_section_path(gallery, section),
      gallery_section_photo_path(gallery, section, photo) ].each do |path|
      get path

      assert_response :success
      assert head_value(/<meta name="description" content="([^"]+)"/).present?, "#{path}: description"
      assert_equal "index, follow, max-image-preview:large", head_value(/<meta name="robots" content="([^"]+)"/), path
      assert_match %r{\Ahttp://www\.example\.com/}, head_value(/<link rel="canonical" href="([^"]+)"/), path
      %w[og:title og:description og:url og:image og:image:width og:image:height og:site_name].each do |prop|
        assert head_value(/property="#{prop}" content="([^"]+)"/).present?, "#{path}: #{prop}"
      end
      assert_equal 1, response.body.scan("<h1").size, "#{path}: exactly one h1"
    end
  end

  test "titles follow the conference site's 'Page | Site' pattern and are escaped once" do
    gallery = create_gallery
    gallery.sections.first.update!(title: "Talks & Q&A")
    create_photo(gallery.sections.first)

    get gallery_section_path(gallery, gallery.sections.first)

    assert_equal "Talks &amp; Q&amp;A, Friendly.rb 2025 photos | Friendly.rb Photos", head_value(%r{<title>(.*?)</title>})
  end

  test "a section page's h1 differs from its gallery page's" do
    gallery = create_gallery
    create_photo(gallery.sections.first)

    get gallery_path(gallery)
    gallery_h1 = head_value(%r{<h1>(.*?)</h1>}m)
    get gallery_section_path(gallery, gallery.sections.first)

    assert_not_equal gallery_h1, head_value(%r{<h1>(.*?)</h1>}m)
  end

  test "structured data links the conference organisation and the breadcrumb trail" do
    gallery = create_gallery
    section = gallery.sections.first
    create_photo(section)

    get gallery_section_path(gallery, section)

    graph = json_ld["@graph"]
    assert_equal "https://friendlyrb.com/#organization", graph.find { |n| n["@type"] == "Organization" }["@id"]
    assert_equal "ImageGallery", graph.find { |n| n["@id"] == "http://www.example.com#{gallery_section_path(gallery, section)}" }["@type"]
    crumbs = graph.find { |n| n["@type"] == "BreadcrumbList" }["itemListElement"].map { |i| i["name"] }
    assert_equal [ "Photo galleries", gallery.title, section.title ], crumbs
  end

  test "absolute URLs use the configured host, not a forwarded one" do
    gallery = create_gallery
    create_photo(gallery.sections.first)
    Rails.configuration.x.canonical_url = "https://photos.friendlyrb.com"

    get gallery_path(gallery), headers: { "X-Forwarded-Host" => "evil.example" }

    assert_equal "https://photos.friendlyrb.com/#{gallery.slug}", head_value(/<link rel="canonical" href="([^"]+)"/)
    assert_match %r{\Ahttps://photos\.friendlyrb\.com/}, head_value(/property="og:image" content="([^"]+)"/)
    assert_no_match(/evil\.example/, response.body)
  ensure
    Rails.configuration.x.canonical_url = nil
  end

  test "a doubled leading slash cannot move the canonical to another host" do
    gallery = create_gallery
    create_photo(gallery.sections.first)

    get "//#{gallery.slug}"

    assert_response :success
    assert_equal "http://www.example.com/#{gallery.slug}", head_value(/<link rel="canonical" href="([^"]+)"/)
    assert_equal "http://www.example.com/#{gallery.slug}", head_value(/property="og:url" content="([^"]+)"/)
  end

  test "an admin preview of an unpublished gallery is noindex" do
    gallery = create_gallery(published: false)
    create_photo(gallery.sections.first)
    sign_in users(:admin)

    get gallery_path(gallery)

    assert_equal "noindex, nofollow", head_value(/<meta name="robots" content="([^"]+)"/)
  end

  test "the sign-in page is noindex" do
    get new_user_session_path

    assert_equal "noindex, nofollow", head_value(/<meta name="robots" content="([^"]+)"/)
  end

  test "the sitemap lists published galleries and their sections with images, and nothing unpublished" do
    gallery = create_gallery
    create_photo(gallery.sections.first)
    draft = create_gallery(slug: "draft", published: false)
    create_photo(draft.sections.first)

    get sitemap_path

    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_match(/public/, response.headers["Cache-Control"])
    xml = Nokogiri::XML(response.body)
    locs = xml.xpath("//xmlns:url/xmlns:loc").map(&:text)
    assert_includes locs, "http://www.example.com/#{gallery.slug}"
    assert_includes locs, "http://www.example.com/#{gallery.slug}/day-1"
    assert locs.none? { |l| l.include?("draft") }, "unpublished galleries must not be listed"
    assert_operator xml.xpath("//image:loc", "image" => "http://www.google.com/schemas/sitemap-image/1.1").size, :>=, 2
  end

  test "robots.txt points at the sitemap and keeps the admin out" do
    get "/robots.txt"

    assert_response :success
    assert_match %r{^Sitemap: http://www\.example\.com/sitemap\.xml$}, response.body
    assert_match %r{^Disallow: /avo$}, response.body
  end

  test "crawlers are not turned away by the modern-browser check" do
    get root_path, headers: { "User-Agent" => "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" }
    assert_response :success

    get root_path, headers: { "User-Agent" => "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)" }
    assert_response :success
  end
end
