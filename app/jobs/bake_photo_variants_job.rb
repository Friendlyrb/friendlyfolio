# Generates every derivative for one photo and marks it displayable.
#
# One job per photo rather than one per variant: nine jobs each for a bulk
# import is how you end up with seventeen thousand rows in a SQLite queue.
class BakePhotoVariantsJob < ApplicationJob
  queue_as :default

  def perform(photo)
    return if photo.derivatives_ready?

    photo.bake_variants!
  end
end
