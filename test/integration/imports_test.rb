require "test_helper"

class ImportsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @gallery = create_gallery(sections: {})
    sign_in users(:admin)
  end

  def upload_blob(fixture: "landscape.jpg")
    ActiveStorage::Blob.create_and_upload!(
      io: File.open(Rails.root.join("test/fixtures/files", fixture)),
      filename: fixture,
      content_type: "image/jpeg"
    )
  end

  test "the import page is closed to anonymous visitors" do
    sign_out :user

    get new_admin_import_path

    assert_response :redirect
  end

  test "importing creates the photo and the section named by the folder" do
    blob = upload_blob

    post admin_imports_path, params: {
      gallery_slug: @gallery.slug, section_slug: "day-1",
      filename: "DSC_0001.jpg", signed_id: blob.signed_id
    }

    assert_response :success
    assert_equal "imported", response.parsed_body["status"]

    section = @gallery.sections.find_by(slug: "day-1")
    assert section, "the folder name should have created a section"
    assert_equal "Day 1", section.title
    assert_equal 1, section.photos.count
    assert_equal "DSC_0001.jpg", section.photos.first.original_filename
  end

  test "an existing section is reused rather than duplicated" do
    @gallery.sections.create!(slug: "day-1", title: "Day 1", position: 1)

    post admin_imports_path, params: {
      gallery_slug: @gallery.slug, section_slug: "day-1",
      filename: "a.jpg", signed_id: upload_blob.signed_id
    }

    assert_response :success
    assert_equal 1, @gallery.sections.count
  end

  test "re-importing the same file is skipped, not duplicated" do
    blob = upload_blob
    params = { gallery_slug: @gallery.slug, section_slug: "day-1",
               filename: "a.jpg", signed_id: blob.signed_id }

    post admin_imports_path, params: params
    assert_equal "imported", response.parsed_body["status"]

    post admin_imports_path, params: params.merge(signed_id: upload_blob.signed_id)

    assert_equal "skipped", response.parsed_body["status"]
    assert_equal 1, @gallery.sections.find_by(slug: "day-1").photos.count
  end

  test "a photo carrying GPS is rejected and leaves nothing behind" do
    blob = upload_blob
    # Stand in for a located original: the detector runs on attach, so this
    # forces the branch the importer must handle.
    Photo.define_method(:has_location_data?) { true }

    post admin_imports_path, params: {
      gallery_slug: @gallery.slug, section_slug: "day-1",
      filename: "a.jpg", signed_id: blob.signed_id
    }

    assert_response :unprocessable_content
    assert_equal "rejected", response.parsed_body["status"]
    assert_match(/GPS/, response.parsed_body["reason"])
    assert_equal 0, Photo.count, "a rejected photo must not be left in the database"
  ensure
    Photo.remove_method(:has_location_data?)
  end

  test "importing enqueues one bake job per photo" do
    assert_enqueued_jobs 1, only: BakePhotoVariantsJob do
      post admin_imports_path, params: {
        gallery_slug: @gallery.slug, section_slug: "day-1",
        filename: "a.jpg", signed_id: upload_blob.signed_id
      }
    end
  end

  test "an unknown gallery 404s rather than creating anything" do
    post admin_imports_path, params: {
      gallery_slug: "nope", section_slug: "day-1",
      filename: "a.jpg", signed_id: upload_blob.signed_id
    }

    assert_response :not_found
  end
end
