class Photo < ApplicationRecord
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

  has_one_attached :image do |attachable|
    VARIANTS.each do |name, transformations|
      # preprocessed handles the ongoing case -- an admin adding a photo or two.
      # The bulk import does NOT rely on this: baking 1,916 photos this way
      # would enqueue ~17,250 jobs into SQLite. See lib/tasks/photos.rake.
      attachable.variant name, **transformations, preprocessed: true
    end
  end

  after_commit :extract_image_metadata, on: [ :create, :update ], if: -> { image.attached? && width.nil? }

  validates :position, presence: true

  # Only photos whose derivatives exist are ever rendered. Otherwise a photo
  # added to a live gallery would be served before its variants were baked, and
  # the representation controller generates a missing variant synchronously
  # inside the request.
  scope :displayable, -> { where.not(derivatives_ready_at: nil) }

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
end
