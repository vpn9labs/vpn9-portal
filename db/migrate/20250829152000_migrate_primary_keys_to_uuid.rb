class MigratePrimaryKeysToUuid < ActiveRecord::Migration[8.0]
  def up
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    # 1) Add UUID columns to all tables that still use integer PKs
    add_uuid(:admins)
    add_uuid(:affiliates)
    add_uuid(:locations)
    add_uuid(:plans)
    add_uuid(:users)
    add_uuid(:launch_notifications)
    add_uuid(:webhook_logs)
    add_uuid(:relays)
    add_uuid(:relay_bandwidth_stats)
    add_uuid(:relay_monthly_summaries)
    add_uuid(:admin_sessions)
    add_uuid(:affiliate_clicks)
    add_uuid(:devices)
    add_uuid(:payouts)
    add_uuid(:referrals)
    add_uuid(:sessions)
    add_uuid(:subscriptions)
    # payments already uses UUID PKs; device_sessions created with id: :uuid

    # 2) Convert foreign keys to reference UUIDs (via the temporary uuid columns)
    # Admins → AdminSessions
    migrate_fk_to_uuid child: :admin_sessions, parent: :admins, column: :admin_id

    # Affiliates → many
    migrate_fk_to_uuid child: :affiliate_clicks, parent: :affiliates, column: :affiliate_id
    migrate_fk_to_uuid child: :referrals,        parent: :affiliates, column: :affiliate_id
    migrate_fk_to_uuid child: :payouts,          parent: :affiliates, column: :affiliate_id
    migrate_fk_to_uuid child: :commissions,      parent: :affiliates, column: :affiliate_id

    # Users → many
    migrate_fk_to_uuid child: :devices,          parent: :users, column: :user_id
    migrate_fk_to_uuid child: :sessions,         parent: :users, column: :user_id, on_delete: :cascade
    migrate_fk_to_uuid child: :referrals,        parent: :users, column: :user_id
    migrate_fk_to_uuid child: :subscriptions,    parent: :users, column: :user_id, on_delete: :restrict
    migrate_fk_to_uuid child: :payments,         parent: :users, column: :user_id, on_delete: :restrict
    migrate_fk_to_uuid child: :device_sessions,  parent: :users, column: :user_id if table_exists?(:device_sessions) && column_exists?(:device_sessions, :user_id)

    # Plans → Subscriptions, Payments
    migrate_fk_to_uuid child: :subscriptions, parent: :plans, column: :plan_id
    migrate_fk_to_uuid child: :payments,      parent: :plans, column: :plan_id

    # Subscriptions → Payments
    migrate_fk_to_uuid child: :payments, parent: :subscriptions, column: :subscription_id

    # Locations → Relays
    migrate_fk_to_uuid child: :relays, parent: :locations, column: :location_id

    # Relays → Relay stats
    migrate_fk_to_uuid child: :relay_bandwidth_stats,    parent: :relays, column: :relay_id
    migrate_fk_to_uuid child: :relay_monthly_summaries,  parent: :relays, column: :relay_id

    # Referrals → Commissions
    migrate_fk_to_uuid child: :commissions, parent: :referrals, column: :referral_id

    # Payouts → Commissions
    migrate_fk_to_uuid child: :commissions, parent: :payouts, column: :payout_id

    # 3) Finalize PK swaps (drop integer id, rename uuid → id) in dependency order
    finalize_pk_swap(:admins)
    finalize_pk_swap(:affiliates)
    finalize_pk_swap(:users)
    finalize_pk_swap(:plans)
    finalize_pk_swap(:locations)
    finalize_pk_swap(:relays)
    finalize_pk_swap(:referrals)
    finalize_pk_swap(:payouts)

    # Leaf tables or ones only referenced by already-swapped parents
    finalize_pk_swap(:admin_sessions)
    finalize_pk_swap(:affiliate_clicks)
    finalize_pk_swap(:devices)
    finalize_pk_swap(:launch_notifications)
    finalize_pk_swap(:webhook_logs)
    finalize_pk_swap(:relay_bandwidth_stats)
    finalize_pk_swap(:relay_monthly_summaries)
    finalize_pk_swap(:sessions)
    finalize_pk_swap(:subscriptions)
    finalize_pk_swap(:payments) # no-op if already UUID, guarded in helper
    finalize_pk_swap(:plans)    # second call is harmless due to guard
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Switching PKs back from UUIDs is not supported"
  end

  private

  def add_uuid(table)
    return unless table_exists?(table)

    # Skip if ID already uuid
    begin
      id_col = column_for(table, :id)
      return if id_col && (id_col.type.to_s == 'uuid' || id_col.sql_type.to_s == 'uuid')
    rescue
      # Proceed conservatively
    end

    return if column_exists?(table, :uuid, :uuid)
    add_column table, :uuid, :uuid, default: "gen_random_uuid()", null: false
    # Unique index so children can reference parent.uuid before we swap to id
    add_index table, :uuid, unique: true unless index_exists?(table, :uuid)
  end

  def finalize_pk_swap(table)
    return unless table_exists?(table)

    # If already using UUID id, skip
    begin
      id_col = column_for(table, :id)
      return if id_col && (id_col.type.to_s == 'uuid' || id_col.sql_type.to_s == 'uuid')
    rescue
      # proceed
    end

    return unless column_exists?(table, :uuid, :uuid)

    # Drop existing primary key constraint (name: <table>_pkey in Postgres)
    begin
      execute "ALTER TABLE #{quote_table_name(table)} DROP CONSTRAINT #{quote_table_name("#{table}_pkey")} CASCADE"
    rescue
      # ignore if missing
    end

    # Drop old integer id, rename uuid → id, and add primary key
    remove_column table, :id if column_exists?(table, :id)
    rename_column table, :uuid, :id
    execute "ALTER TABLE #{quote_table_name(table)} ADD PRIMARY KEY (id)"

    # Drop the now-redundant unique index on the old uuid column if it still exists (name may still be index_<table>_on_uuid)
    if index_name_exists?(table, "index_#{table}_on_uuid")
      remove_index table, name: "index_#{table}_on_uuid"
    end
  end

  def migrate_fk_to_uuid(child:, parent:, column:, on_delete: nil)
    return unless table_exists?(child) && table_exists?(parent)
    return unless column_exists?(child, column)

    new_col = "#{column}_uuid".to_sym
    add_column child, new_col, :uuid

    # Backfill using parent.uuid mapping
    execute <<~SQL
      UPDATE #{quote_table_name(child)} c
         SET #{quote_column_name(new_col)} = p.uuid
        FROM #{quote_table_name(parent)} p
       WHERE c.#{quote_column_name(column)} = p.id
    SQL

    # Constraints and indexes
    begin
      remove_foreign_key child, parent
    rescue
      # ignore if FK absent or named differently
    end

    # Drop the old column; existing indexes on it will be dropped automatically
    remove_column child, column

    # Rename the new UUID column into place
    rename_column child, new_col, column

    # Recreate common indexes lost during drop (based on typical schema)
    recreate_common_indexes(child, column)

    # Re-add FK referencing parent's uuid (which will later be renamed to id)
    options = { column: column, primary_key: :uuid }
    options[:on_delete] = on_delete if on_delete
    add_foreign_key child, parent, **options
  end

  def recreate_common_indexes(table, column)
    # This method re-adds indexes known from the schema for each table/column combo.
    case [table.to_sym, column.to_sym]
    when [:admin_sessions, :admin_id]
      add_index :admin_sessions, :admin_id unless index_exists?(:admin_sessions, :admin_id)

    when [:affiliate_clicks, :affiliate_id]
      add_index :affiliate_clicks, :affiliate_id unless index_exists?(:affiliate_clicks, :affiliate_id)
      add_index :affiliate_clicks, [:affiliate_id, :created_at] unless index_exists?(:affiliate_clicks, [:affiliate_id, :created_at])

    when [:referrals, :affiliate_id]
      add_index :referrals, :affiliate_id unless index_exists?(:referrals, :affiliate_id)
      add_index :referrals, [:affiliate_id, :status] unless index_exists?(:referrals, [:affiliate_id, :status])
    when [:referrals, :user_id]
      add_index :referrals, :user_id, unique: true, name: 'index_referrals_on_user_id_unique' unless index_exists?(:referrals, :user_id, name: 'index_referrals_on_user_id_unique')

    when [:payouts, :affiliate_id]
      add_index :payouts, :affiliate_id unless index_exists?(:payouts, :affiliate_id)
      add_index :payouts, [:affiliate_id, :status] unless index_exists?(:payouts, [:affiliate_id, :status])
      add_index :payouts, :status unless index_exists?(:payouts, :status)

    when [:commissions, :affiliate_id]
      add_index :commissions, :affiliate_id unless index_exists?(:commissions, :affiliate_id)
    when [:commissions, :referral_id]
      add_index :commissions, :referral_id unless index_exists?(:commissions, :referral_id)
    when [:commissions, :payout_id]
      add_index :commissions, :payout_id unless index_exists?(:commissions, :payout_id)

    when [:devices, :user_id]
      add_index :devices, :user_id unless index_exists?(:devices, :user_id)
      add_index :devices, [:user_id, :status] unless index_exists?(:devices, [:user_id, :status])

    when [:sessions, :user_id]
      add_index :sessions, :user_id unless index_exists?(:sessions, :user_id)

    when [:subscriptions, :user_id]
      add_index :subscriptions, :user_id unless index_exists?(:subscriptions, :user_id)
      add_index :subscriptions, :status unless index_exists?(:subscriptions, :status)
      add_index :subscriptions, :expires_at unless index_exists?(:subscriptions, :expires_at)
    when [:subscriptions, :plan_id]
      add_index :subscriptions, :plan_id unless index_exists?(:subscriptions, :plan_id)

    when [:payments, :user_id]
      add_index :payments, :user_id unless index_exists?(:payments, :user_id)
    when [:payments, :plan_id]
      add_index :payments, :plan_id unless index_exists?(:payments, :plan_id)
    when [:payments, :subscription_id]
      add_index :payments, :subscription_id unless index_exists?(:payments, :subscription_id)

    when [:relays, :location_id]
      add_index :relays, :location_id unless index_exists?(:relays, :location_id)

    when [:relay_bandwidth_stats, :relay_id]
      add_index :relay_bandwidth_stats, :relay_id unless index_exists?(:relay_bandwidth_stats, :relay_id)
      add_index :relay_bandwidth_stats, [:relay_id, :date], unique: true, name: 'index_relay_bandwidth_stats_on_relay_id_and_date' unless index_exists?(:relay_bandwidth_stats, [:relay_id, :date], name: 'index_relay_bandwidth_stats_on_relay_id_and_date')

    when [:relay_monthly_summaries, :relay_id]
      add_index :relay_monthly_summaries, :relay_id unless index_exists?(:relay_monthly_summaries, :relay_id)
      add_index :relay_monthly_summaries, [:relay_id, :year, :month], unique: true, name: 'index_relay_monthly_summaries_on_relay_id_and_year_and_month' unless index_exists?(:relay_monthly_summaries, [:relay_id, :year, :month], name: 'index_relay_monthly_summaries_on_relay_id_and_year_and_month')
      add_index :relay_monthly_summaries, [:year, :month] unless index_exists?(:relay_monthly_summaries, [:year, :month])

    when [:device_sessions, :user_id]
      add_index :device_sessions, :user_id unless index_exists?(:device_sessions, :user_id)
      add_index :device_sessions, :device_id unless index_exists?(:device_sessions, :device_id)
      add_index :device_sessions, :active unless index_exists?(:device_sessions, :active)
      add_index :device_sessions, :refresh_token_hash, unique: true unless index_exists?(:device_sessions, :refresh_token_hash)
      add_index :device_sessions, [:user_id, :device_id], unique: true unless index_exists?(:device_sessions, [:user_id, :device_id])
    end
  end

  def column_for(table, column)
    columns(table).find { |c| c.name.to_s == column.to_s }
  end
end
