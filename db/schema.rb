# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_21_101201) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "galleries", force: :cascade do |t|
    t.integer "cover_photo_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.date "held_on"
    t.string "photographer"
    t.datetime "published_at"
    t.integer "sections_count", default: 0, null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["published_at"], name: "index_galleries_on_published_at"
    t.index ["slug"], name: "index_galleries_on_slug", unique: true
  end

  create_table "photos", force: :cascade do |t|
    t.string "blurhash"
    t.datetime "created_at", null: false
    t.datetime "derivatives_ready_at"
    t.integer "derived_from_blob_id"
    t.string "dominant_color"
    t.boolean "has_location_data", default: false, null: false
    t.integer "height"
    t.string "original_filename"
    t.integer "position", default: 0, null: false
    t.integer "section_id", null: false
    t.string "source_digest"
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["section_id", "position"], name: "index_photos_on_section_id_and_position"
    t.index ["section_id", "source_digest"], name: "index_photos_on_section_id_and_source_digest", unique: true
    t.index ["section_id"], name: "index_photos_on_section_id"
  end

  create_table "sections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "gallery_id", null: false
    t.integer "photos_count", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["gallery_id", "position"], name: "index_sections_on_gallery_id_and_position"
    t.index ["gallery_id", "slug"], name: "index_sections_on_gallery_id_and_slug", unique: true
    t.index ["gallery_id"], name: "index_sections_on_gallery_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "photos", "sections"
  add_foreign_key "sections", "galleries"
end
