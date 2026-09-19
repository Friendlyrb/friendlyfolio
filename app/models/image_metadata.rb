# Derives the columns the photo wall depends on, and enforces the one privacy
# guarantee that cannot be left to a runbook.
#
# Runs for every attachment path -- the import task and the admin alike -- so no
# entry point can produce a photo the wall cannot lay out, or one that leaks an
# attendee's location.
module ImageMetadata
  # EXIF keys vips exposes for location data.
  GPS_FIELDS = /gps/i

  module_function

  def apply(photo)
    photo.image.blob.open do |file|
      image = Vips::Image.new_from_file(file.path, access: :sequential)

      photo.update_columns(
        width: image.width,
        height: image.height,
        dominant_color: dominant_color(file.path),
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
  def located?(image)
    image.get_fields.grep(GPS_FIELDS).any?
  rescue StandardError
    false
  end

  # One vips call: shrink the whole image to a single pixel and read it. Cheaper
  # and simpler than any placeholder scheme that needs a gem and a JS decoder,
  # and the tile already has its space reserved, so the colour is all that is
  # missing.
  def dominant_color(path)
    pixel = Vips::Image.thumbnail(path, 1, height: 1).colourspace(:srgb)
    r, g, b = pixel.getpoint(0, 0).first(3).map { |v| v.to_i.clamp(0, 255) }
    format("#%02x%02x%02x", r, g, b)
  rescue StandardError
    "#e5e5e5"
  end
end
