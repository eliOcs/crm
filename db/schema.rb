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

ActiveRecord::Schema[8.1].define(version: 2025_11_29_171536) do
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

  create_table "companies", force: :cascade do |t|
    t.string "commercial_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "domain"
    t.string "industry"
    t.string "legal_name"
    t.string "location"
    t.integer "parent_company_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.datetime "web_enriched_at"
    t.string "website"
    t.index ["parent_company_id"], name: "index_companies_on_parent_company_id"
    t.index ["user_id", "domain"], name: "index_companies_on_user_id_and_domain", unique: true
    t.index ["user_id"], name: "index_companies_on_user_id"
  end

  create_table "companies_contacts", id: false, force: :cascade do |t|
    t.integer "company_id", null: false
    t.integer "contact_id", null: false
    t.index ["company_id", "contact_id"], name: "index_companies_contacts_on_company_id_and_contact_id", unique: true
    t.index ["company_id"], name: "index_companies_contacts_on_company_id"
    t.index ["contact_id", "company_id"], name: "index_companies_contacts_on_contact_id_and_company_id"
    t.index ["contact_id"], name: "index_companies_contacts_on_contact_id"
  end

  create_table "contacts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "job_role"
    t.string "name"
    t.json "phone_numbers", default: []
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "email"], name: "index_contacts_on_user_id_and_email", unique: true
    t.index ["user_id"], name: "index_contacts_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "companies", "companies", column: "parent_company_id"
  add_foreign_key "companies", "users"
  add_foreign_key "companies_contacts", "companies"
  add_foreign_key "companies_contacts", "contacts"
  add_foreign_key "contacts", "users"
  add_foreign_key "sessions", "users"
end
