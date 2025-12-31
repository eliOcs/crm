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

ActiveRecord::Schema[8.1].define(version: 2025_12_31_100003) do
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

  create_table "audit_logs", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "auditable_id", null: false
    t.string "auditable_type", null: false
    t.datetime "created_at", null: false
    t.json "field_changes", default: {}
    t.string "message"
    t.json "metadata", default: {}
    t.integer "source_email_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["auditable_type", "auditable_id"], name: "index_audit_logs_on_auditable_type_and_auditable_id"
    t.index ["source_email_id"], name: "index_audit_logs_on_source_email_id"
    t.index ["user_id", "created_at"], name: "index_audit_logs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "companies", force: :cascade do |t|
    t.string "commercial_name"
    t.datetime "created_at", null: false
    t.string "domain"
    t.string "legal_name"
    t.string "location"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.string "vat_id"
    t.string "website"
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
    t.string "department"
    t.string "email", null: false
    t.string "job_role"
    t.string "name"
    t.json "phone_numbers", default: []
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id", "email"], name: "index_contacts_on_user_id_and_email", unique: true
    t.index ["user_id"], name: "index_contacts_on_user_id"
  end

  create_table "email_attachments", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.string "checksum", null: false
    t.string "content_id"
    t.string "content_type", null: false
    t.datetime "created_at", null: false
    t.integer "email_id", null: false
    t.string "filename", null: false
    t.boolean "inline", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["content_id"], name: "index_email_attachments_on_content_id"
    t.index ["email_id", "inline"], name: "index_email_attachments_on_email_id_and_inline"
    t.index ["email_id"], name: "index_email_attachments_on_email_id"
  end

  create_table "emails", force: :cascade do |t|
    t.text "body_html"
    t.text "body_plain"
    t.json "cc_addresses", default: []
    t.integer "contact_id"
    t.datetime "created_at", null: false
    t.json "from_address", null: false
    t.string "in_reply_to"
    t.string "message_id"
    t.json "references", default: []
    t.datetime "sent_at", null: false
    t.string "source_path"
    t.string "subject"
    t.json "to_addresses", default: []
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["contact_id"], name: "index_emails_on_contact_id"
    t.index ["in_reply_to"], name: "index_emails_on_in_reply_to"
    t.index ["user_id", "message_id"], name: "index_emails_on_user_id_and_message_id", unique: true, where: "message_id IS NOT NULL"
    t.index ["user_id", "sent_at"], name: "index_emails_on_user_id_and_sent_at"
    t.index ["user_id"], name: "index_emails_on_user_id"
  end

  create_table "microsoft_credentials", force: :cascade do |t|
    t.text "access_token", null: false
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "expires_at", null: false
    t.datetime "last_sync_at"
    t.string "microsoft_user_id", null: false
    t.text "refresh_token", null: false
    t.string "scope"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["microsoft_user_id"], name: "index_microsoft_credentials_on_microsoft_user_id", unique: true
    t.index ["user_id"], name: "index_microsoft_credentials_on_user_id", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "tasks", force: :cascade do |t|
    t.integer "company_id"
    t.integer "contact_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.date "due_date"
    t.string "name", null: false
    t.string "status", default: "incoming", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["company_id"], name: "index_tasks_on_company_id"
    t.index ["contact_id"], name: "index_tasks_on_contact_id"
    t.index ["due_date"], name: "index_tasks_on_due_date"
    t.index ["status"], name: "index_tasks_on_status"
    t.index ["user_id"], name: "index_tasks_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "locale", default: "en", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "audit_logs", "emails", column: "source_email_id"
  add_foreign_key "audit_logs", "users"
  add_foreign_key "companies", "users"
  add_foreign_key "companies_contacts", "companies"
  add_foreign_key "companies_contacts", "contacts"
  add_foreign_key "contacts", "users"
  add_foreign_key "email_attachments", "emails"
  add_foreign_key "emails", "contacts"
  add_foreign_key "emails", "users"
  add_foreign_key "microsoft_credentials", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "tasks", "companies"
  add_foreign_key "tasks", "contacts"
  add_foreign_key "tasks", "users"
end
