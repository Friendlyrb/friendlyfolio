require "test_helper"

class GalleryTest < ActiveSupport::TestCase
  test "slug must be unique" do
    Gallery.create!(slug: "2025", title: "A")
    duplicate = Gallery.new(slug: "2025", title: "B")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "published scope excludes galleries with no published_at" do
    draft = Gallery.create!(slug: "draft", title: "Draft")
    live = Gallery.create!(slug: "live", title: "Live", published_at: Time.current)

    assert_includes Gallery.published, live
    assert_not_includes Gallery.published, draft
  end

  test "sections come back in position order regardless of insertion order" do
    gallery = Gallery.create!(slug: "2025", title: "A")
    gallery.sections.create!(slug: "second", title: "Second", position: 2)
    gallery.sections.create!(slug: "first", title: "First", position: 1)

    assert_equal %w[first second], gallery.sections.reload.map(&:slug)
  end

  test "cover falls back to the first photo when cover_photo is absent" do
    gallery = create_gallery
    photo = create_photo(gallery.sections.first)

    assert_equal photo, gallery.reload.cover
  end

  test "destroying a gallery destroys its sections and photos" do
    gallery = create_gallery
    create_photo(gallery.sections.first)

    assert_difference [ "Section.count", "Photo.count" ], -1 do
      gallery.destroy
    end
  end

  test "to_param uses the slug so URLs read as the edition year" do
    assert_equal "2025", Gallery.new(slug: "2025").to_param
  end
end
