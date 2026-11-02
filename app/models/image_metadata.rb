# Derives the columns the photo wall depends on, and enforces the one privacy
# guarantee that cannot be left to a runbook.
#
# Runs for every attachment path -- the import task and the admin alike -- so no
# entry point can produce a photo the wall cannot lay out, or one that leaks an
# attendee's location.
module ImageMetadata
  # EXIF keys vips exposes for location data.
  GPS_FIELDS = /gps/i
  # libvips hands XMP over as one opaque packet ("xmp-data") rather than as
  # fields, so GPS written only there -- which `exiftool -gps:all=` leaves
  # behind -- has to be found in the packet itself.
  # Case-insensitive, and matched after dropping NUL bytes so a UTF-16 packet
  # reads the same as a UTF-8 one.
  XMP_GPS = /gps\s*(?:lat|long)/i

  module_function

  def apply(photo)
    photo.image.blob.open do |file|
      image = Vips::Image.new_from_file(file.path, access: :sequential)

      photo.update_columns(
        width: image.width,
        height: image.height,
        dominant_color: dominant_color(file.path),
        blurhash: blurhash(file.path),
        has_location_data: located?(image),
        original_filename: photo.original_filename.presence || photo.image.filename.to_s,
        updated_at: Time.current
      )
    end
  end

  # The download button hands out the original file, so stripping derivatives
  # alone would still leak coordinates to anyone who downloads a photo. Removing
  # GPS losslessly needs exiftool, which is not a runtime dependency here -- so
  # this detects it and the model refuses to publish, rather than silently
  # re-encoding the photographer's file and losing quality.
  #
  # An image that cannot be inspected counts as located: an unknown verdict is
  # not a clean one, and the cost of a false positive is a re-upload.
  def located?(image)
    fields = image.get_fields
    return true if fields.grep(GPS_FIELDS).any?

    fields.include?("xmp-data") && image.get("xmp-data").to_s.b.delete("\0").match?(XMP_GPS)
  rescue StandardError
    true
  end

  # One vips call: shrink the whole image to a single pixel and read it. This
  # stays the wall's placeholder -- a tile is 400px with its space already
  # reserved, so a flat colour is all that is missing, and a canvas per tile on
  # a wall of hundreds is not. It is also the lightbox's fallback whenever the
  # hash below could not be derived.
  def dominant_color(path)
    pixel = Vips::Image.thumbnail(path, 1, height: 1).colourspace(:srgb)
    r, g, b = pixel.getpoint(0, 0).first(3).map { |v| v.to_i.clamp(0, 255) }
    format("#%02x%02x%02x", r, g, b)
  rescue StandardError
    "#e5e5e5"
  end

  # The lightbox placeholder: one photo filling the screen is the case a flat
  # colour serves badly.
  #
  # Derived here, from the file the caller already downloaded, rather than
  # through active_storage-blurhash. That gem's analyzer hands vips the *path*
  # of an ImageProcessing tempfile and drops the Tempfile itself; vips opens it
  # lazily, so GC unlinks the file before the pixels are read and every job on a
  # busy worker dies with "unable to open for read". Doing it here also skips a
  # second download of an original this method already has on disk.
  #
  # 32px is generous: the hash is 4x3 components, so everything finer is thrown
  # away by the encoder.
  def blurhash(path)
    thumb = Vips::Image.thumbnail(path, 32).colourspace(:srgb)
    thumb = thumb.extract_band(0, n: 3) if thumb.bands > 3
    Blurhash.encode(thumb.width, thumb.height, thumb.to_a.flatten)
  rescue StandardError
    nil
  end
end
