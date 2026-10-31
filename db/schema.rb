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

ActiveRecord::Schema[8.1].define(version: 2026_10_31_160300) do
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

  create_table "billing_events", force: :cascade do |t|
    t.string "provider", null: false
    t.string "event_id", null: false
    t.string "event_type", null: false
    t.integer "kind"
    t.bigint "user_id"
    t.string "plan"
    t.string "customer_id"
    t.string "subscription_id"
    t.string "payment_id"
    t.integer "amount_cents"
    t.string "currency"
    t.datetime "period_end"
    t.integer "credits"
    t.string "note"
    t.jsonb "payload", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "occurred_at"
    t.string "reference"
    t.index ["provider", "event_id"], name: "index_billing_events_on_provider_and_event_id", unique: true
    t.index ["provider", "payment_id"], name: "index_billing_events_on_provider_and_payment_id"
    t.index ["provider", "subscription_id"], name: "index_billing_events_on_provider_and_subscription_id"
    t.index ["status"], name: "index_billing_events_on_status"
    t.index ["user_id"], name: "index_billing_events_on_user_id"
  end

  create_table "billing_subscriptions", force: :cascade do |t|
    t.string "provider", null: false
    t.string "subscription_id", null: false
    t.bigint "user_id"
    t.string "plan", null: false
    t.string "status", null: false
    t.boolean "cancel_at_period_end", default: false, null: false
    t.datetime "period_end"
    t.datetime "event_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "subscription_id"], name: "index_billing_subscriptions_on_provider_and_subscription_id", unique: true
    t.index ["user_id"], name: "index_billing_subscriptions_on_user_id"
  end

  create_table "checkouts", force: :cascade do |t|
    t.bigint "user_id"
    t.string "provider", null: false
    t.string "plan", null: false
    t.string "token", null: false
    t.integer "status", default: 0, null: false
    t.string "url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_checkouts_on_token", unique: true
    t.index ["user_id", "plan", "status", "created_at"], name: "index_checkouts_on_user_id_and_plan_and_status_and_created_at"
    t.index ["user_id"], name: "index_checkouts_on_user_id"
  end

  create_table "credit_entries", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "delta", null: false
    t.integer "reason", null: false
    t.string "source"
    t.integer "balance_after", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reason", "source"], name: "index_credit_entries_once_per_source", unique: true, where: "((source IS NOT NULL) AND (reason <> ALL (ARRAY[3, 4])))"
    t.index ["user_id", "id"], name: "index_credit_entries_on_user_id_and_id"
    t.check_constraint "balance_after >= 0", name: "credit_entries_balance_not_negative"
    t.check_constraint "delta <> 0", name: "credit_entries_delta_not_zero"
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
    t.string "example_digest"
    t.bigint "user_id"
    t.string "label", limit: 40
    t.index ["purge_after"], name: "index_kits_on_purge_after"
    t.index ["token"], name: "index_kits_on_token", unique: true
    t.index ["user_id"], name: "index_kits_on_user_id"
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

  create_table "provider_calls", force: :cascade do |t|
    t.bigint "kit_id"
    t.string "operation", null: false
    t.string "input_hash", null: false
    t.decimal "units", precision: 8, scale: 2, default: "0.0", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "response", default: {}, null: false
    t.date "day", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["day"], name: "index_provider_calls_on_day"
    t.index ["kit_id"], name: "index_provider_calls_on_kit_id"
    t.index ["operation", "input_hash"], name: "index_provider_calls_on_operation_and_input_hash", unique: true
  end

  create_table "renders", force: :cascade do |t|
    t.bigint "kit_id", null: false
    t.bigint "photo_id", null: false
    t.bigint "reference_photo_id"
    t.integer "kind", default: 0, null: false
    t.string "look_key"
    t.jsonb "effects", default: [], null: false
    t.integer "status", default: 0, null: false
    t.string "failure_reason"
    t.string "external_id"
    t.datetime "started_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "input_hash"
    t.index ["external_id"], name: "index_renders_on_external_id"
    t.index ["input_hash"], name: "index_renders_on_input_hash"
    t.index ["kit_id"], name: "index_renders_on_kit_id"
    t.index ["photo_id"], name: "index_renders_on_photo_id"
    t.index ["reference_photo_id"], name: "index_renders_on_reference_photo_id"
  end

  create_table "shares", force: :cascade do |t|
    t.bigint "kit_id", null: false
    t.string "token", null: false
    t.integer "audience", default: 0, null: false
    t.integer "scope", default: 0, null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kit_id"], name: "index_shares_on_kit_id"
    t.index ["token"], name: "index_shares_on_token", unique: true
  end

  create_table "signup_grants", force: :cascade do |t|
    t.string "account_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_digest"], name: "index_signup_grants_on_account_digest", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "provider", null: false
    t.string "uid", null: false
    t.string "email", null: false
    t.string "name"
    t.string "avatar_url"
    t.datetime "clinic_until"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "billing_customer_id"
    t.index ["billing_customer_id"], name: "index_users_on_billing_customer_id", unique: true, where: "(billing_customer_id IS NOT NULL)"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "billing_events", "users", on_delete: :nullify
  add_foreign_key "billing_subscriptions", "users", on_delete: :nullify
  add_foreign_key "checkouts", "users", on_delete: :nullify
  add_foreign_key "credit_entries", "users"
  add_foreign_key "kits", "users"
  add_foreign_key "photos", "kits"
  add_foreign_key "provider_calls", "kits", on_delete: :nullify
  add_foreign_key "renders", "kits"
  add_foreign_key "renders", "photos"
  add_foreign_key "renders", "photos", column: "reference_photo_id"
  add_foreign_key "shares", "kits"
end
