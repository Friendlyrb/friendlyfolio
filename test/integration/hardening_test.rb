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

  test "the early sign-in throttle counts every spelling of the sign-in path" do
    by_ip = Rack::Attack.throttles["logins/ip"]

    %w[/users/sign_in /users/sign_in.html /users/sign_in/ //users//sign_in].each do |path|
      # PATH_INFO set directly: env_for would parse "//users" as a host.
      env = Rack::MockRequest.env_for("/", method: "POST", "REMOTE_ADDR" => "203.0.113.9").merge("PATH_INFO" => path)
      request = Rack::Attack::Request.new(env)

      assert_equal "203.0.113.9", by_ip.block.call(request), path
    end
  end

  test "sign-in is limited per account, including JSON bodies" do
    Users::SessionsController::LOGIN_ATTEMPTS.clear
    body = { user: { email: "Admin@FriendlyRB.com ", password: "wrong" } }

    # Spread across addresses, so only the per-account limit can trip.
    10.times { |i| post user_session_path, params: body, as: :json, headers: { "REMOTE_ADDR" => "203.0.113.#{i}" } }
    post user_session_path, params: body, as: :json, headers: { "REMOTE_ADDR" => "203.0.113.99" }

    assert_response :too_many_requests
  ensure
    Users::SessionsController::LOGIN_ATTEMPTS.clear
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
