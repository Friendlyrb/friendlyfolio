class AddDerivedFromBlobIdToPhotos < ActiveRecord::Migration[8.1]
  # Which blob the derived columns and the baked variants actually came from.
  # Without it there is no way to tell a photo whose image was replaced from one
  # that was always this image, because the attachment is reloaded by the time
  # the record's after_commit runs and reports no change.
  def change
    add_column :photos, :derived_from_blob_id, :integer
  end
end
