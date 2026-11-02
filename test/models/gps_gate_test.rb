require "test_helper"
require "vips"

# The one privacy promise: no published original carries an attendee's
# location. These pin every path that once let one through.
class GpsGateTest < ActiveSupport::TestCase
  setup do
    @gallery = create_gallery
    @section = @gallery.sections.first
  end

  # A real JPEG whose only GPS is in an XMP packet -- the state
  # `exiftool -gps:all=` leaves behind. Built here so no fixture carries GPS.
  def xmp_only_gps_jpeg
    xmp = %(<x:xmpmeta xmlns:x="adobe:ns:meta/"><rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">) +
          %(<rdf:Description xmlns:exif="http://ns.adobe.com/exif/1.0/" exif:GPSLatitude="45,26.4N" exif:GPSLongitude="21,13.8E"/>) +
          %(</rdf:RDF></x:xmpmeta>)
    payload = "http://ns.adobe.com/xap/1.0/\0".b + xmp.b
    segment = "\xFF\xE1".b + [ payload.bytesize + 2 ].pack("n") + payload
    jpeg = File.binread(Rails.root.join("test/fixtures/files/landscape.jpg"))
    jpeg[0, 2] + segment + jpeg[2..]
  end

  test "GPS held only in XMP is detected" do
    Tempfile.create([ "xmp-gps", ".jpg" ], binmode: true) do |file|
      file.write(xmp_only_gps_jpeg)
      file.flush
      image = Vips::Image.new_from_file(file.path)

      assert_empty image.get_fields.grep(/gps/i), "precondition: no EXIF GPS field"
      assert ImageMetadata.located?(image)
    end
  end

  test "GPS in a UTF-16 XMP packet is detected too" do
    image = Object.new
    def image.get_fields = [ "xmp-data" ]
    def image.get(_) = "<exif:GPSLatitude>45</exif:GPSLatitude>".encode("UTF-16LE").b

    assert ImageMetadata.located?(image)
  end

  test "a clean photo is not located" do
    assert_not ImageMetadata.located?(Vips::Image.new_from_file(Rails.root.join("test/fixtures/files/landscape.jpg").to_s))
  end

  test "an image that cannot be inspected counts as located" do
    broken = Object.new
    def broken.get_fields = raise(Vips::Error, "read failed")

    assert ImageMetadata.located?(broken)
  end

  test "a failed metadata scan flags the photo instead of leaving it clean" do
    photo = create_photo(@section, ready: false)
    photo.update_columns(has_location_data: false, width: nil)

    stubbing(ImageMetadata, :apply, ->(_) { raise Errno::ECONNRESET }) { photo.extract_image_metadata }

    assert photo.reload.has_location_data?
    assert_not photo.scanned?
  end

  test "a flagged photo is never displayable, whoever set derivatives_ready_at" do
    photo = create_photo(@section)
    assert_includes Photo.displayable, photo

    photo.update_columns(has_location_data: true)

    assert_not_includes Photo.displayable, photo
  end

  test "replacing a live photo's image hides it until the new one is re-scanned and baked" do
    photo = create_photo(@section)

    Photo.without_auto_bake do
      photo.image.attach(io: File.open(Rails.root.join("test/fixtures/files/portrait.jpg")),
                         filename: "portrait.jpg", content_type: "image/jpeg")
    end

    assert_nil photo.reload.derivatives_ready_at
  end

  test "a gallery cover must be its own displayable photo" do
    own = create_photo(@section)
    other = create_gallery(slug: "2024")
    foreign = create_photo(other.sections.first)

    @gallery.update!(cover_photo: foreign)
    assert_equal own, Gallery.find(@gallery.id).cover, "another gallery's photo must not be the cover"

    own.update_columns(has_location_data: true)
    assert_nil Gallery.find(@gallery.id).cover, "a located photo must not be the cover"
  end

  test "dominant colour must be a plain hex colour" do
    photo = create_photo(@section)

    assert_not photo.update(dominant_color: "red;background:url(x)")
    assert photo.update(dominant_color: "#a1b2c3")
  end
end
