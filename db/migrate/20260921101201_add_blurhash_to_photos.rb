class AddBlurhashToPhotos < ActiveRecord::Migration[8.1]
  def change
    add_column :photos, :blurhash, :string
  end
end
