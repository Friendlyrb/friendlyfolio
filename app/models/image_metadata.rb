# Derives the columns the photo wall depends on, straight from the attached
# image. Runs for every attachment path -- the import task and the admin alike
# -- so no entry point can produce a photo the wall cannot lay out.
module ImageMetadata
  module_function

  def apply(photo)
    photo.image.blob.open do |file|
      image = Vips::Image.new_from_file(file.path, access: :sequential)

      photo.update_columns(
        width: image.width,
        height: image.height,
        dominant_color: dominant_color(file.path),
        original_filename: photo.original_filename.presence || photo.image.filename.to_s,
        updated_at: Time.current
      )
    end
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
