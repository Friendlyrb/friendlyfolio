# Generates every derivative for one photo and marks it displayable.
#
# One job per photo rather than one per variant: nine jobs each for a bulk
# import is how you end up with seventeen thousand rows in a SQLite queue.
class BakePhotoVariantsJob < ApplicationJob
  queue_as :default

  # The importer destroys a photo it rejects for carrying GPS, which can happen
  # before this job is picked up. A vanished photo is not a failure.
  discard_on ActiveJob::DeserializationError

  def perform(photo)
    return if photo.derivatives_ready?

    photo.bake_variants!
  end
end
