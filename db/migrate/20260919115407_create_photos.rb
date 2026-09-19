class CreatePhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :photos do |t|
      t.references :section, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.string :original_filename

      # Denormalised from the attached image so the wall can reserve each tile's
      # exact space without an N+1 across active_storage_blobs. Without these
      # there is no aspect ratio, and without an aspect ratio the layout shifts.
      t.integer :width
      t.integer :height
      t.string :dominant_color

      # Ingest idempotency: re-running an import must not duplicate photos.
      t.string :source_digest

      # nil until every derivative exists. Public scopes require it, so a photo
      # added to a live gallery cannot be rendered before it is baked -- which
      # would make a visitor's request generate variants synchronously.
      t.datetime :derivatives_ready_at

      t.timestamps
    end

    add_index :photos, [ :section_id, :position ]
    add_index :photos, [ :section_id, :source_digest ], unique: true
  end
end
