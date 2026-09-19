class Section < ApplicationRecord
  belongs_to :gallery, counter_cache: :sections_count, inverse_of: :sections
  has_many :photos, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :section

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
  #
  # Counts rather than loading every id: at 342 photos the pluck-and-index
  # version read the whole section on every single deep link.
  def page_for(photo)
    preceding = photos.displayable
                      .where("position < :pos OR (position = :pos AND id < :id)", pos: photo.position, id: photo.id)
                      .count
    (preceding / PER_PAGE) + 1
  end

  def photos_on(page)
    photos.displayable.offset((page - 1) * PER_PAGE).limit(PER_PAGE)
  end

  # The lightbox manifest only ever holds one page, so stepping off either end
  # needs a server-computed link into the adjacent page. Without these, next on
  # the last tile navigates to the tile you are already looking at.
  def first_photo_on(page)
    return nil if page < 1 || page > page_count

    photos_on(page).first
  end

  def last_photo_on(page)
    return nil if page < 1 || page > page_count

    photos_on(page).last
  end
end
