require "test_helper"

class SectionTest < ActiveSupport::TestCase
  test "slug is unique within a gallery but may repeat across galleries" do
    a = create_gallery(slug: "2024")
    b = create_gallery(slug: "2025")

    assert b.sections.find_by(slug: "day-1").present?
    duplicate = a.sections.build(slug: "day-1", title: "Again")
    assert_not duplicate.valid?
  end

  test "page_for resolves a photo to the page containing it" do
    section = create_gallery.sections.first
    ids = (1..5).map { |i| create_photo(section, position: i).id }

    # With a small section everything is page one.
    assert_equal 1, section.page_for(Photo.find(ids.last))
  end

  test "a section at or below the page size does not paginate" do
    section = create_gallery.sections.first
    create_photo(section)

    assert_not section.paginated?
    assert_equal 1, section.page_count
  end
end
