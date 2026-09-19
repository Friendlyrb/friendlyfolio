class CreateGalleries < ActiveRecord::Migration[8.1]
  def change
    create_table :galleries do |t|
      t.string :slug, null: false
      t.string :title, null: false
      t.date :held_on
      t.string :photographer
      t.text :description
      # nil until published; every public lookup scopes on this.
      t.datetime :published_at
      t.integer :cover_photo_id
      t.integer :photos_count, null: false, default: 0

      t.timestamps
    end

    add_index :galleries, :slug, unique: true
    add_index :galleries, :published_at
  end
end
