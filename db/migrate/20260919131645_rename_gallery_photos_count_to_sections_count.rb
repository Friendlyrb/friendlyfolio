class RenameGalleryPhotosCountToSectionsCount < ActiveRecord::Migration[8.1]
  # The counter on galleries was maintained by Section's counter_cache, so it
  # counted sections while being named and displayed as a photo count. The name
  # now says what it holds; the photo count is summed from the sections, which
  # is one cheap query against a handful of rows.
  def change
    rename_column :galleries, :photos_count, :sections_count
  end
end
