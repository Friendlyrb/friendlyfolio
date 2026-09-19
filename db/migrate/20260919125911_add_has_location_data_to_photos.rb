class AddHasLocationDataToPhotos < ActiveRecord::Migration[8.1]
  def change
    add_column :photos, :has_location_data, :boolean, null: false, default: false
  end
end
