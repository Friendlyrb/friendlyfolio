require "test_helper"

class PhotoTest < ActiveSupport::TestCase
  setup { @section = create_gallery.sections.first }

  test "attaching records dimensions and a dominant colour" do
    photo = create_photo(@section)

    assert_equal 3000, photo.width
    assert_equal 2000, photo.height
    assert_match(/\A#[0-9a-f]{6}\z/, photo.dominant_color)
  end

  test "aspect ratio comes from the stored dimensions" do
    assert_in_delta 1.5, create_photo(@section).aspect_ratio, 0.001
  end

  test "a portrait photo records portrait dimensions" do
    photo = create_photo(@section, fixture: "portrait.jpg")

    assert_operator photo.height, :>, photo.width
    assert_operator photo.aspect_ratio, :<, 1
  end

  test "aspect ratio falls back rather than dividing by zero" do
    assert_equal 1.5, Photo.new(width: 0, height: 0).aspect_ratio
  end

  test "nine variants are declared and each resolves distinctly" do
    assert_equal 9, Photo::VARIANTS.size

    photo = create_photo(@section)
    keys = Photo::VARIANTS.keys.map { |v| photo.image.variant(v).variation.key }

    assert_equal keys.size, keys.uniq.size
  end

  test "the sharing variant is a JPEG, because it leaves the browser" do
    assert_equal :jpeg, Photo::VARIANTS[:share_jpeg][:format]
  end

  test "every variant strips metadata" do
    Photo::VARIANTS.each do |name, opts|
      assert opts[:saver][:strip], "#{name} must strip metadata"
    end
  end

  test "displayable excludes photos whose derivatives are not baked" do
    pending = create_photo(@section, position: 1, ready: false)
    ready = create_photo(@section, position: 2, ready: true)

    assert_includes Photo.displayable, ready
    assert_not_includes Photo.displayable, pending
  end

  test "a generated variant carries no EXIF" do
    photo = create_photo(@section)
    variant = photo.image.variant(:thumb_webp).processed

    variant.image.blob.open do |f|
      image = Vips::Image.new_from_file(f.path)
      assert_empty image.get_fields.grep(/exif|gps/i)
    end
  end
end
