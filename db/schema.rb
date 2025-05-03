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

ActiveRecord::Schema[8.0].define(version: 2025_05_03_210552) do
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

  create_table "app_entities", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "token"
    t.index ["token"], name: "index_app_entities_on_token", unique: true
    t.index ["user_id"], name: "index_app_entities_on_user_id"
  end

  create_table "dyn_1", force: :cascade do |t|
    t.string "name"
    t.integer "age"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "avatar"
  end

  create_table "dyn_2", force: :cascade do |t|
    t.string "name"
    t.string "ag222"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dynamic_fields", force: :cascade do |t|
    t.integer "dynamic_table_id", null: false
    t.string "name"
    t.string "field_type"
    t.boolean "required"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dynamic_table_id"], name: "index_dynamic_fields_on_dynamic_table_id"
  end

  create_table "dynamic_tables", force: :cascade do |t|
    t.string "table_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "api_identifier"
    t.integer "app_entity_id", null: false
    t.string "webhook_url"
    t.index ["api_identifier"], name: "index_dynamic_tables_on_api_identifier", unique: true
    t.index ["app_entity_id"], name: "index_dynamic_tables_on_app_entity_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "username"
    t.string "email"
    t.string "password_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "app_entities", "users"
  add_foreign_key "dynamic_fields", "dynamic_tables"
  add_foreign_key "dynamic_tables", "app_entities"
end
