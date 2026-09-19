class Photo < ApplicationRecord
  # The download button hands out the original, so a photo carrying GPS must
  # never become displayable -- stripping derivatives alone would still leak an
  # attendee's location to anyone who downloads it.
  class LocationDataPresent < StandardError; end

  belongs_to :section, counter_cache: :photos_count, inverse_of: :photos

  # Wall tiles, then lightbox, then the two sizes that leave the browser.
  #
  # AVIF reached Baseline "widely available" in July 2026, so AVIF + WebP covers
  # essentially everyone and a third JPEG display tier would only cost encode
  # time and disk. The JPEG below is not a display tier: it is for the "for
  # sharing" download, where the recipient's operating system has to open it,
  # and for og:image, where link unfurlers do not decode AVIF.
  VARIANTS = {
    thumb_avif: { resize_to_limit: [ 400, 400 ], format: :avif, saver: { Q: 50, effort: 4, strip: true } },
    thumb_webp: { resize_to_limit: [ 400, 400 ], format: :webp, saver: { Q: 72, strip: true } },
    wall_avif: { resize_to_limit: [ 800, 800 ], format: :avif, saver: { Q: 50, effort: 4, strip: true } },
    wall_webp: { resize_to_limit: [ 800, 800 ], format: :webp, saver: { Q: 72, strip: true } },
    zoom_avif: { resize_to_limit: [ 1280, 1280 ], format: :avif, saver: { Q: 52, effort: 4, strip: true } },
    zoom_webp: { resize_to_limit: [ 1280, 1280 ], format: :webp, saver: { Q: 78, strip: true } },
    large_avif: { resize_to_limit: [ 2048, 2048 ], format: :avif, saver: { Q: 52, effort: 4, strip: true } },
    large_webp: { resize_to_limit: [ 2048, 2048 ], format: :webp, saver: { Q: 78, strip: true } },
    share_jpeg: { resize_to_limit: [ 2048, 2048 ], format: :jpeg, saver: { quality: 80, strip: true } }
  }.freeze

  # Deliberately NOT declared `preprocessed: true`. That flag is a property of
  # the attachment declaration, not of the call site: Active Storage runs
  # transform_variants_later in an after_create_commit on every attach, so it
  # would enqueue nine jobs per photo -- roughly 17,250 for the full import --
  # with no way for the bulk path to opt out. Baking is driven explicitly
  # instead, by BakePhotoVariantsJob for single uploads and inline by
  # lib/tasks/photos.rake for the import.
  has_one_attached :image do |attachable|
    VARIANTS.each { |name, transformations| attachable.variant name, **transformations }
  end

  # Keyed on the blob actually changing, not on the derived columns being blank.
  # Guarding on `width.nil?` meant replacing a live photo's image in the admin
  # skipped both the GPS check and the re-bake: the columns were already
  # populated from the *old* file, so the new one kept the old dimensions, kept
  # has_location_data false, and was never re-baked -- and the download handed
  # out the new original with its coordinates intact.
  after_commit :refresh_image_derivatives, on: [ :create, :update ], if: :image_changed?

  validates :position, presence: true

  # Only photos whose derivatives exist are ever rendered. Otherwise a photo
  # added to a live gallery would be served before its variants were baked, and
  # the representation controller generates a missing variant synchronously
  # inside the request.
  scope :displayable, -> { where.not(derivatives_ready_at: nil) }

  # Without this every tile queries for its attachment and blob -- several
  # hundred queries on a full wall. Variant records are deliberately NOT eager
  # loaded: a proxy-mode URL is built from the blob's signed id, the variation
  # key and the filename, so it never reads them, and loading them would add
  # thousands of unused objects per page.
  scope :with_images, -> { includes(image_attachment: :blob) }

  def aspect_ratio
    return 1.5 if width.to_i.zero? || height.to_i.zero?

    (width.to_f / height).round(4)
  end

  def derivatives_ready? = derivatives_ready_at.present?

  def download_filename
    original_filename.presence || "photo-#{id}.jpg"
  end

  # Width, height and dominant colour hang off the attachment rather than the
  # import task, so a photo added through the admin arrives with them too.
  # Without dimensions the wall cannot reserve the tile's space.
  def extract_image_metadata
    ImageMetadata.apply(self)
  rescue StandardError => e
    Rails.logger.warn("Photo##{id} metadata extraction failed: #{e.message}")
  end

  def image_changed?
    return false unless image.attached?

    derived_from_blob_id != image.blob.id
  end

  # A replaced image is a different photo as far as everything downstream is
  # concerned, so the old derivatives and the old verdict on its metadata are
  # both stale until this finishes.
  def refresh_image_derivatives
    update_columns(derivatives_ready_at: nil, derived_from_blob_id: image.blob.id)
    extract_image_metadata
    bake_variants_later
  end

  # Builds every variant and marks the photo displayable. Called inline by the
  # import task and in the background for a single admin upload.
  def bake_variants!
    if has_location_data?
      raise LocationDataPresent,
            "#{download_filename} still carries GPS EXIF. Strip it from the source first: " \
            "exiftool -gps:all= -overwrite_original <dir>"
    end

    VARIANTS.each_key { |name| image.variant(name).processed }
    update!(derivatives_ready_at: Time.current)
  end

  # Suppresses the automatic bake so a bulk import can do the work inline
  # rather than filling the queue with one job per photo.
  def self.without_auto_bake
    previous = Thread.current[:photo_skip_auto_bake]
    Thread.current[:photo_skip_auto_bake] = true
    yield
  ensure
    Thread.current[:photo_skip_auto_bake] = previous
  end

  def self.auto_bake? = !Thread.current[:photo_skip_auto_bake]

  private

  def bake_variants_later
    BakePhotoVariantsJob.perform_later(self) if self.class.auto_bake?
  end
end
