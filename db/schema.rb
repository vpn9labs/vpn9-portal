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

ActiveRecord::Schema[8.0].define(version: 2025_08_29_101000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "admin_sessions", force: :cascade do |t|
    t.bigint "admin_id", null: false
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["admin_id"], name: "index_admin_sessions_on_admin_id"
  end

  create_table "admins", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
  end

  create_table "affiliate_clicks", force: :cascade do |t|
    t.bigint "affiliate_id", null: false
    t.string "ip_hash"
    t.string "user_agent_hash"
    t.string "landing_page"
    t.string "referrer"
    t.boolean "converted", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["affiliate_id", "created_at"], name: "index_affiliate_clicks_on_affiliate_id_and_created_at"
    t.index ["affiliate_id"], name: "index_affiliate_clicks_on_affiliate_id"
    t.index ["ip_hash", "created_at"], name: "index_affiliate_clicks_on_ip_hash_and_created_at"
  end

  create_table "affiliates", force: :cascade do |t|
    t.string "code", null: false
    t.string "name"
    t.string "email"
    t.string "payout_address"
    t.string "payout_currency", default: "btc"
    t.decimal "commission_rate", precision: 5, scale: 2, default: "20.0"
    t.integer "status", default: 0
    t.decimal "lifetime_earnings", precision: 10, scale: 2, default: "0.0"
    t.decimal "pending_balance", precision: 10, scale: 2, default: "0.0"
    t.decimal "paid_out_total", precision: 10, scale: 2, default: "0.0"
    t.integer "cookie_duration_days", default: 30
    t.integer "attribution_window_days", default: 30
    t.json "settings"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "minimum_payout_amount", precision: 10, scale: 2, default: "100.0", null: false
    t.text "notes"
    t.string "password_digest"
    t.string "company_name"
    t.string "website"
    t.text "promotional_methods"
    t.integer "expected_referrals"
    t.string "tax_id"
    t.string "address"
    t.string "city"
    t.string "state"
    t.string "country"
    t.string "postal_code"
    t.string "phone"
    t.boolean "terms_accepted", default: false
    t.index ["code"], name: "index_affiliates_on_code", unique: true
    t.index ["email"], name: "index_affiliates_on_email"
    t.index ["status"], name: "index_affiliates_on_status"
  end

  create_table "commissions", force: :cascade do |t|
    t.bigint "affiliate_id", null: false
    t.uuid "payment_id", null: false
    t.bigint "referral_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency", default: "USD"
    t.decimal "commission_rate", precision: 5, scale: 2
    t.integer "status", default: 0
    t.datetime "approved_at"
    t.datetime "paid_at"
    t.string "payout_transaction_id"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "payout_id"
    t.index ["affiliate_id", "status"], name: "index_commissions_on_affiliate_id_and_status"
    t.index ["affiliate_id"], name: "index_commissions_on_affiliate_id"
    t.index ["payment_id"], name: "index_commissions_on_payment_id"
    t.index ["payment_id"], name: "index_commissions_on_payment_id_unique", unique: true
    t.index ["payout_id"], name: "index_commissions_on_payout_id"
    t.index ["referral_id"], name: "index_commissions_on_referral_id"
  end

  create_table "devices", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.text "public_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "status", default: 0, null: false
    t.index ["name"], name: "index_devices_on_name", unique: true
    t.index ["public_key"], name: "index_devices_on_public_key", unique: true
    t.index ["status"], name: "index_devices_on_status"
    t.index ["user_id", "status"], name: "index_devices_on_user_id_and_status"
    t.index ["user_id"], name: "index_devices_on_user_id"
  end

  create_table "launch_notifications", force: :cascade do |t|
    t.string "email", null: false
    t.string "user_agent"
    t.string "referrer"
    t.boolean "notified", default: false, null: false
    t.string "source"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_launch_notifications_on_created_at"
    t.index ["email"], name: "index_launch_notifications_on_email", unique: true
    t.index ["notified"], name: "index_launch_notifications_on_notified"
  end

  create_table "locations", force: :cascade do |t|
    t.string "country_code", limit: 2
    t.string "city"
    t.decimal "latitude"
    t.decimal "longitude"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "payments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "plan_id", null: false
    t.bigint "subscription_id"
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency", null: false
    t.integer "status", default: 0, null: false
    t.string "processor_id"
    t.string "crypto_currency"
    t.decimal "crypto_amount", precision: 18, scale: 8
    t.string "payment_address"
    t.jsonb "processor_data", default: {}
    t.string "transaction_id"
    t.datetime "paid_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_secret"
    t.index ["id"], name: "index_payments_on_id", unique: true
    t.index ["paid_at"], name: "index_payments_on_paid_at"
    t.index ["plan_id"], name: "index_payments_on_plan_id"
    t.index ["processor_id"], name: "index_payments_on_processor_id", unique: true
    t.index ["status"], name: "index_payments_on_status"
    t.index ["subscription_id"], name: "index_payments_on_subscription_id"
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "payouts", force: :cascade do |t|
    t.bigint "affiliate_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "currency", default: "USD", null: false
    t.integer "status", default: 0, null: false
    t.string "payout_method", null: false
    t.string "payout_address", null: false
    t.string "transaction_id"
    t.datetime "approved_at"
    t.datetime "processed_at"
    t.datetime "completed_at"
    t.datetime "failed_at"
    t.datetime "cancelled_at"
    t.text "admin_notes"
    t.text "failure_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["affiliate_id", "status"], name: "index_payouts_on_affiliate_id_and_status"
    t.index ["affiliate_id"], name: "index_payouts_on_affiliate_id"
    t.index ["status"], name: "index_payouts_on_status"
    t.index ["transaction_id"], name: "index_payouts_on_transaction_id"
  end

  create_table "plans", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.decimal "price", precision: 10, scale: 2, null: false
    t.string "currency", default: "USD", null: false
    t.integer "duration_days"
    t.boolean "active", default: true, null: false
    t.jsonb "features", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "device_limit", default: 5, null: false
    t.boolean "lifetime", default: false, null: false
    t.index ["active"], name: "index_plans_on_active"
  end

  create_table "referrals", force: :cascade do |t|
    t.bigint "affiliate_id", null: false
    t.bigint "user_id", null: false
    t.string "referral_code"
    t.string "landing_page"
    t.string "ip_hash"
    t.datetime "clicked_at"
    t.datetime "converted_at"
    t.integer "status", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["affiliate_id", "status"], name: "index_referrals_on_affiliate_id_and_status"
    t.index ["affiliate_id"], name: "index_referrals_on_affiliate_id"
    t.index ["user_id"], name: "index_referrals_on_user_id"
    t.index ["user_id"], name: "index_referrals_on_user_id_unique", unique: true
  end

  create_table "relay_bandwidth_stats", force: :cascade do |t|
    t.bigint "relay_id", null: false
    t.date "date", null: false
    t.bigint "bandwidth_in", default: 0, null: false
    t.bigint "bandwidth_out", default: 0, null: false
    t.integer "peak_connections", default: 0
    t.integer "unique_tokens", default: 0
    t.float "avg_cpu_usage"
    t.float "avg_memory_usage"
    t.float "uptime_percentage", default: 100.0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_relay_bandwidth_stats_on_date"
    t.index ["relay_id", "date"], name: "index_relay_bandwidth_stats_on_relay_id_and_date", unique: true
    t.index ["relay_id"], name: "index_relay_bandwidth_stats_on_relay_id"
  end

  create_table "relay_monthly_summaries", force: :cascade do |t|
    t.bigint "relay_id", null: false
    t.integer "year", null: false
    t.integer "month", null: false
    t.bigint "total_bandwidth_in", default: 0, null: false
    t.bigint "total_bandwidth_out", default: 0, null: false
    t.bigint "total_bandwidth", default: 0, null: false
    t.integer "max_concurrent_connections", default: 0
    t.float "avg_daily_bandwidth"
    t.float "cost_estimate"
    t.integer "days_active", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["relay_id", "year", "month"], name: "index_relay_monthly_summaries_on_relay_id_and_year_and_month", unique: true
    t.index ["relay_id"], name: "index_relay_monthly_summaries_on_relay_id"
    t.index ["year", "month"], name: "index_relay_monthly_summaries_on_year_and_month"
  end

  create_table "relays", force: :cascade do |t|
    t.string "name"
    t.string "hostname"
    t.string "ipv4_address"
    t.string "ipv6_address"
    t.string "public_key"
    t.integer "port"
    t.integer "status"
    t.bigint "location_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["location_id"], name: "index_relays_on_location_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "plan_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "started_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_subscriptions_on_expires_at"
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.integer "status", limit: 2, default: 0
    t.binary "recovery_code"
    t.string "email_address"
    t.datetime "last_seen", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.binary "passphrase_hash"
    t.datetime "deleted_at"
    t.text "deletion_reason"
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true, where: "(email_address IS NOT NULL)"
  end

  create_table "webhook_logs", force: :cascade do |t|
    t.string "webhookable_type", null: false
    t.string "ip_address", null: false
    t.string "status"
    t.datetime "processed_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "webhookable_id", null: false
    t.index ["webhookable_type", "webhookable_id"], name: "index_webhook_logs_on_webhookable"
  end

  add_foreign_key "admin_sessions", "admins"
  add_foreign_key "affiliate_clicks", "affiliates"
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
  add_foreign_key "relay_bandwidth_stats", "relays"
  add_foreign_key "relay_monthly_summaries", "relays"
  add_foreign_key "relays", "locations"
  add_foreign_key "sessions", "users", on_delete: :cascade
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "subscriptions", "users", on_delete: :restrict
end
