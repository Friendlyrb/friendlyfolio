class CreateSections < ActiveRecord::Migration[8.1]
  def change
    create_table :sections do |t|
      t.references :gallery, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :title, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.integer :photos_count, null: false, default: 0

      t.timestamps
    end

    add_index :sections, [ :gallery_id, :slug ], unique: true
    add_index :sections, [ :gallery_id, :position ]
  end
end
