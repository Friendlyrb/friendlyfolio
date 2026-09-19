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

  test "page_for resolves a photo past the page size to its own page" do
    section = create_gallery.sections.first
    stub_const_per_page(2) do
      ids = (1..5).map { |i| create_photo(section, position: i) }

      assert_equal 1, section.page_for(ids[0])
      assert_equal 1, section.page_for(ids[1])
      assert_equal 2, section.page_for(ids[2])
      assert_equal 3, section.page_for(ids[4])
    end
  end

  test "adjacent-page lookups return the neighbouring photo, or nil at the ends" do
    section = create_gallery.sections.first
    stub_const_per_page(2) do
      photos = (1..5).map { |i| create_photo(section, position: i) }

      assert_equal photos[2], section.first_photo_on(2)
      assert_equal photos[1], section.last_photo_on(1)
      assert_nil section.first_photo_on(0)
      assert_nil section.last_photo_on(99)
    end
  end

  private

  # PER_PAGE is 300 in production; exercising pagination with 300 real
  # attachments would take minutes, so the boundary is tested at 2.
  def stub_const_per_page(value)
    original = Section::PER_PAGE
    Section.send(:remove_const, :PER_PAGE)
    Section.const_set(:PER_PAGE, value)
    yield
  ensure
    Section.send(:remove_const, :PER_PAGE)
    Section.const_set(:PER_PAGE, original)
  end
end
