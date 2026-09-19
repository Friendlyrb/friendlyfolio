class Gallery < ApplicationRecord
  has_many :sections, -> { order(:position) }, dependent: :destroy, inverse_of: :gallery
  has_many :photos, through: :sections
  belongs_to :cover_photo, class_name: "Photo", optional: true

  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/, message: "must be lowercase letters, numbers and dashes" }
  validates :title, presence: true

  scope :published, -> { where.not(published_at: nil) }
  scope :newest_first, -> { order(held_on: :desc, id: :desc) }

  def to_param = slug

  def published? = published_at.present?

  # Summed from the sections rather than counter-cached on the gallery: photos
  # belong to sections, so a counter_cache here would have counted sections.
  # A gallery has a handful of sections, so this is one cheap query.
  def photos_count = sections.sum(:photos_count)

  # Falls back to the first photo so a gallery whose cover was deleted still
  # renders instead of raising.
  def cover
    return @cover if defined?(@cover)

    @cover = cover_photo || photos.displayable.first
  end
end
