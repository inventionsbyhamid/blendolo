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

ActiveRecord::Schema[8.1].define(version: 2026_10_31_080100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "kits", force: :cascade do |t|
    t.string "token", null: false
    t.integer "path", default: 0, null: false
    t.integer "tremor"
    t.integer "pinch"
    t.integer "one_hand"
    t.integer "fatigue"
    t.integer "near_vision"
    t.integer "hands_today", default: 1, null: false
    t.integer "retention_days", default: 30, null: false
    t.datetime "consented_at"
    t.datetime "last_active_at", null: false
    t.datetime "purge_after", null: false
    t.string "chosen_look_key"
    t.jsonb "routine", default: [], null: false
    t.string "example_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["purge_after"], name: "index_kits_on_purge_after"
    t.index ["token"], name: "index_kits_on_token", unique: true
  end

  create_table "photos", force: :cascade do |t|
    t.bigint "kit_id", null: false
    t.integer "kind", default: 0, null: false
    t.string "source", null: false
    t.string "sha256"
    t.integer "width"
    t.integer "height"
    t.jsonb "sampled", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kit_id"], name: "index_photos_on_kit_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "photos", "kits"
end
