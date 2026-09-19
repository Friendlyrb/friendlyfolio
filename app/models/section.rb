class Section < ApplicationRecord
  belongs_to :gallery, counter_cache: :photos_count, inverse_of: :sections
  has_many :photos, -> { order(:position) }, dependent: :destroy, inverse_of: :section

  validates :slug, presence: true,
                   uniqueness: { scope: :gallery_id },
                   format: { with: /\A[a-z0-9][a-z0-9-]*\z/, message: "must be lowercase letters, numbers and dashes" }
  validates :title, presence: true

  # Above this, a section paginates rather than rendering every tile. The
  # reference product returns 2.75 MB of HTML for its 342-tile section, which is
  # the failure this avoids. The number is a judgement call, not a measurement.
  PER_PAGE = 300

  def to_param = slug

  def paginated? = photos.displayable.count > PER_PAGE

  def page_count
    [ (photos.displayable.count / PER_PAGE.to_f).ceil, 1 ].max
  end

  # A deep link has to resolve to the page holding its photo. Rendering page one
  # for a photo on page two opens the wall with nothing to zoom.
  def page_for(photo)
    index = photos.displayable.pluck(:id).index(photo.id)
    return 1 if index.nil?

    (index / PER_PAGE) + 1
  end
end
