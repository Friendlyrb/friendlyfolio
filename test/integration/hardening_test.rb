require "test_helper"

class HardeningTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the download redirect is relative, so a forged forwarded host cannot redirect cached downloads" do
    gallery = create_gallery
    section = gallery.sections.first
    photo = create_photo(section)

    get download_gallery_section_photo_path(gallery, section, photo), headers: { "X-Forwarded-Host" => "evil.example" }

    assert_response :found
    assert_match %r{\A/rails/active_storage/blobs/redirect/}, response.headers["Location"]
  end

  test "anonymous visitors cannot create direct uploads" do
    post rails_direct_uploads_path, params: { blob: { filename: "a.jpg", byte_size: 10, checksum: "x", content_type: "image/jpeg" } }, as: :json

    assert_response :unauthorized
    assert_equal 0, ActiveStorage::Blob.count
  end

  test "signed-in direct uploads are capped in size" do
    sign_in users(:admin)

    post rails_direct_uploads_path, params: { blob: { filename: "a.jpg", byte_size: 300.megabytes, checksum: "x", content_type: "image/jpeg" } }, as: :json

    assert_response :unprocessable_content
  end

  test "the sign-in throttles count every format of the sign-in path" do
    by_ip = Rack::Attack.throttles["logins/ip"]
    by_email = Rack::Attack.throttles["logins/email"]

    %w[/users/sign_in /users/sign_in.html /users/sign_in.json].each do |path|
      env = Rack::MockRequest.env_for(path, method: "POST", params: { user: { email: " Admin@Example.test " } }, "REMOTE_ADDR" => "203.0.113.9")
      request = Rack::Attack::Request.new(env)

      assert_equal "203.0.113.9", by_ip.block.call(request), path
      assert_equal "admin@example.test", by_email.block.call(request), path
    end
  end

  test "sign-in has no format variants" do
    post "/users/sign_in.json", params: { user: { email: "admin@friendlyrb.com", password: "x" } }

    assert_response :not_found
  end

  test "a public page carrying a flash is not publicly cacheable" do
    sign_in users(:admin)
    delete destroy_user_session_path
    follow_redirect!

    assert_match(/private/, response.headers["Cache-Control"])
  end

  test "public pages vary on Turbo-Frame and set no cookie" do
    gallery = create_gallery
    create_photo(gallery.sections.first)

    get gallery_section_path(gallery, gallery.sections.first)

    assert_match(/Turbo-Frame/, response.headers["Vary"])
    assert_match(/public/, response.headers["Cache-Control"])
    assert_nil response.headers["Set-Cookie"]
  end

  test "an absurd page number is clamped rather than breaking the query" do
    gallery = create_gallery
    create_photo(gallery.sections.first)

    get gallery_section_path(gallery, gallery.sections.first, page: "1#{"0" * 30}")

    assert_response :success
  end

  test "pages send a content security policy that only allows same-origin scripts" do
    get root_path

    csp = response.headers["Content-Security-Policy"]
    assert_match(/script-src 'self' 'nonce-/, csp)
    assert_match(/object-src 'none'/, csp)
    assert_match(/frame-ancestors 'self'/, csp)
  end

  test "the importer says when a photo could not be checked, rather than claiming GPS" do
    gallery = create_gallery(sections: {})
    sign_in users(:admin)
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(Rails.root.join("test/fixtures/files/landscape.jpg")),
                                                  filename: "a.jpg", content_type: "image/jpeg")

    stubbing(ImageMetadata, :apply, ->(_) { raise Errno::ECONNRESET }) do
      post admin_imports_path, params: { gallery_slug: gallery.slug, section_slug: "day-1", filename: "a.jpg", signed_id: blob.signed_id }
    end

    assert_response :unprocessable_content
    assert_match(/could not be checked/, response.parsed_body["reason"])
    assert_equal 0, Photo.count
  end

  test "a section name that parameterizes to nothing falls back instead of failing" do
    gallery = create_gallery(sections: {})
    sign_in users(:admin)
    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(Rails.root.join("test/fixtures/files/landscape.jpg")),
                                                  filename: "a.jpg", content_type: "image/jpeg")

    post admin_imports_path, params: { gallery_slug: gallery.slug, section_slug: "Ζιουα", filename: "a.jpg", signed_id: blob.signed_id }

    assert_equal "photos", response.parsed_body["section"]
  end
end
