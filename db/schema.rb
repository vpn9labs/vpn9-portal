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

ActiveRecord::Schema[8.1].define(version: 2025_10_22_165312) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "admin_sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "admin_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["admin_id"], name: "index_admin_sessions_on_admin_id"
    t.index ["id"], name: "index_admin_sessions_on_id", unique: true
  end

  create_table "admins", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["id"], name: "index_admins_on_id", unique: true
  end

  create_table "affiliate_clicks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "affiliate_id"
    t.boolean "converted", default: false
    t.datetime "created_at", null: false
    t.string "ip_hash"
    t.string "landing_page"
    t.string "referrer"
    t.datetime "updated_at", null: false
    t.string "user_agent_hash"
    t.index ["affiliate_id", "created_at"], name: "index_affiliate_clicks_on_affiliate_id_and_created_at"
    t.index ["affiliate_id"], name: "index_affiliate_clicks_on_affiliate_id"
    t.index ["id"], name: "index_affiliate_clicks_on_id", unique: true
    t.index ["ip_hash", "created_at"], name: "index_affiliate_clicks_on_ip_hash_and_created_at"
  end

  create_table "affiliates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "address"
    t.integer "attribution_window_days", default: 30
    t.string "city"
    t.string "code", null: false
    t.decimal "commission_rate", precision: 5, scale: 2, default: "20.0"
    t.string "company_name"
    t.integer "cookie_duration_days", default: 30
    t.string "country"
    t.datetime "created_at", null: false
    t.string "email"
    t.integer "expected_referrals"
    t.decimal "lifetime_earnings", precision: 10, scale: 2, default: "0.0"
    t.decimal "minimum_payout_amount", precision: 10, scale: 2, default: "100.0", null: false
    t.string "name"
    t.text "notes"
    t.decimal "paid_out_total", precision: 10, scale: 2, default: "0.0"
    t.string "password_digest"
    t.string "payout_address"
    t.string "payout_currency", default: "btc"
    t.decimal "pending_balance", precision: 10, scale: 2, default: "0.0"
    t.string "phone"
    t.string "postal_code"
    t.text "promotional_methods"
    t.json "settings"
    t.string "state"
    t.integer "status", default: 0
    t.string "tax_id"
    t.boolean "terms_accepted", default: false
    t.datetime "updated_at", null: false
    t.string "website"
    t.index ["code"], name: "index_affiliates_on_code", unique: true
    t.index ["email"], name: "index_affiliates_on_email"
    t.index ["id"], name: "index_affiliates_on_id", unique: true
    t.index ["status"], name: "index_affiliates_on_status"
  end

  create_table "api_refresh_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "client_label"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.string "token_hash", null: false
    t.datetime "updated_at", null: false
    t.integer "usage_count", default: 0, null: false
    t.uuid "user_id", null: false
    t.index ["expires_at"], name: "index_api_refresh_tokens_on_expires_at"
    t.index ["token_hash"], name: "index_api_refresh_tokens_on_token_hash", unique: true
    t.index ["user_id"], name: "index_api_refresh_tokens_on_user_id"
  end

  create_table "commissions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "affiliate_id"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "approved_at"
    t.decimal "commission_rate", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.string "currency", default: "USD"
    t.text "notes"
    t.datetime "paid_at"
    t.uuid "payment_id", null: false
    t.uuid "payout_id"
    t.string "payout_transaction_id"
    t.uuid "referral_id"
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.index ["affiliate_id", "status"], name: "index_commissions_on_affiliate_id_and_status"
    t.index ["affiliate_id"], name: "index_commissions_on_affiliate_id"
    t.index ["id"], name: "index_commissions_on_id", unique: true
    t.index ["payment_id"], name: "index_commissions_on_payment_id"
    t.index ["payment_id"], name: "index_commissions_on_payment_id_unique", unique: true
    t.index ["payout_id"], name: "index_commissions_on_payout_id"
    t.index ["referral_id"], name: "index_commissions_on_referral_id"
  end

  create_table "devices", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "public_key", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["id"], name: "index_devices_on_id", unique: true
    t.index ["name"], name: "index_devices_on_name", unique: true
    t.index ["public_key"], name: "index_devices_on_public_key", unique: true
    t.index ["status"], name: "index_devices_on_status"
    t.index ["user_id", "status"], name: "index_devices_on_user_id_and_status"
    t.index ["user_id"], name: "index_devices_on_user_id"
  end

  create_table "launch_notifications", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.jsonb "metadata", default: {}
    t.boolean "notified", default: false, null: false
    t.string "referrer"
    t.string "source"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["created_at"], name: "index_launch_notifications_on_created_at"
    t.index ["email"], name: "index_launch_notifications_on_email", unique: true
    t.index ["id"], name: "index_launch_notifications_on_id", unique: true
    t.index ["notified"], name: "index_launch_notifications_on_notified"
  end

  create_table "locations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "city"
    t.string "country_code", limit: 2
    t.datetime "created_at", null: false
    t.decimal "latitude"
    t.decimal "longitude"
    t.datetime "updated_at", null: false
    t.index ["id"], name: "index_locations_on_id", unique: true
  end

  create_table "payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.decimal "crypto_amount", precision: 18, scale: 8
    t.string "crypto_currency"
    t.string "currency", null: false
    t.datetime "expires_at"
    t.datetime "paid_at"
    t.string "payment_address"
    t.uuid "plan_id"
    t.jsonb "processor_data", default: {}
    t.string "processor_id"
    t.integer "status", default: 0, null: false
    t.uuid "subscription_id"
    t.string "transaction_id"
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.string "webhook_secret"
    t.index ["id"], name: "index_payments_on_id", unique: true
    t.index ["paid_at"], name: "index_payments_on_paid_at"
    t.index ["plan_id"], name: "index_payments_on_plan_id"
    t.index ["processor_id"], name: "index_payments_on_processor_id", unique: true
    t.index ["status"], name: "index_payments_on_status"
    t.index ["subscription_id"], name: "index_payments_on_subscription_id"
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "payouts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "admin_notes"
    t.uuid "affiliate_id"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.datetime "approved_at"
    t.datetime "cancelled_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.datetime "failed_at"
    t.text "failure_reason"
    t.string "payout_address", null: false
    t.string "payout_method", null: false
    t.datetime "processed_at"
    t.integer "status", default: 0, null: false
    t.string "transaction_id"
    t.datetime "updated_at", null: false
    t.index ["affiliate_id", "status"], name: "index_payouts_on_affiliate_id_and_status"
    t.index ["affiliate_id"], name: "index_payouts_on_affiliate_id"
    t.index ["id"], name: "index_payouts_on_id", unique: true
    t.index ["status"], name: "index_payouts_on_status"
    t.index ["transaction_id"], name: "index_payouts_on_transaction_id"
  end

  create_table "plans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "currency", default: "USD", null: false
    t.text "description"
    t.integer "device_limit", default: 5, null: false
    t.integer "duration_days"
    t.jsonb "features", default: {}
    t.boolean "lifetime", default: false, null: false
    t.string "name", null: false
    t.decimal "price", precision: 10, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_plans_on_active"
    t.index ["id"], name: "index_plans_on_id", unique: true
  end

  create_table "referrals", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "affiliate_id"
    t.datetime "clicked_at"
    t.datetime "converted_at"
    t.datetime "created_at", null: false
    t.string "ip_hash"
    t.string "landing_page"
    t.string "referral_code"
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["affiliate_id", "status"], name: "index_referrals_on_affiliate_id_and_status"
    t.index ["affiliate_id"], name: "index_referrals_on_affiliate_id"
    t.index ["id"], name: "index_referrals_on_id", unique: true
    t.index ["user_id"], name: "index_referrals_on_user_id_unique", unique: true
  end

  create_table "relays", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "ipv4_address"
    t.string "ipv6_address"
    t.uuid "location_id"
    t.string "name"
    t.integer "port"
    t.string "public_key"
    t.integer "status"
    t.datetime "updated_at", null: false
    t.index ["id"], name: "index_relays_on_id", unique: true
    t.index ["location_id"], name: "index_relays_on_location_id"
  end

  create_table "sessions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.uuid "user_id"
    t.index ["id"], name: "index_sessions_on_id", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.uuid "plan_id"
    t.datetime "started_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["expires_at"], name: "index_subscriptions_on_expires_at"
    t.index ["id"], name: "index_subscriptions_on_id", unique: true
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "deletion_reason"
    t.string "email_address"
    t.datetime "last_seen", precision: nil
    t.binary "passphrase_hash"
    t.binary "recovery_code"
    t.integer "status", limit: 2, default: 0
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true, where: "(email_address IS NOT NULL)"
    t.index ["id"], name: "index_users_on_id", unique: true
  end

  create_table "webhook_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address", null: false
    t.datetime "processed_at", precision: nil
    t.string "status"
    t.datetime "updated_at", null: false
    t.uuid "webhookable_id", null: false
    t.string "webhookable_type", null: false
    t.index ["id"], name: "index_webhook_logs_on_id", unique: true
    t.index ["webhookable_type", "webhookable_id"], name: "index_webhook_logs_on_webhookable"
  end

  add_foreign_key "admin_sessions", "admins"
  add_foreign_key "affiliate_clicks", "affiliates"
  add_foreign_key "api_refresh_tokens", "users"
  add_foreign_key "commissions", "affiliates"
  add_foreign_key "commissions", "payments"
  add_foreign_key "commissions", "payouts"
  add_foreign_key "commissions", "referrals"
  add_foreign_key "devices", "users"
  add_foreign_key "payments", "plans"
  add_foreign_key "payments", "subscriptions"
  add_foreign_key "payments", "users", on_delete: :restrict
  add_foreign_key "payouts", "affiliates"
  add_foreign_key "referrals", "affiliates"
  add_foreign_key "referrals", "users"
  add_foreign_key "relays", "locations"
  add_foreign_key "sessions", "users", on_delete: :cascade
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "subscriptions", "users", on_delete: :restrict
end
