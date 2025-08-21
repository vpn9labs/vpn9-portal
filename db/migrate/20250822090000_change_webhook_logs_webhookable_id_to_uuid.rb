class ChangeWebhookLogsWebhookableIdToUuid < ActiveRecord::Migration[8.0]
  def up
    # Remove composite index if present
    remove_index :webhook_logs, name: "index_webhook_logs_on_webhookable" rescue nil

    # Drop and recreate the column as UUID to avoid invalid cast issues
    remove_column :webhook_logs, :webhookable_id
    add_column :webhook_logs, :webhookable_id, :uuid, null: false

    add_index :webhook_logs, [ :webhookable_type, :webhookable_id ], name: "index_webhook_logs_on_webhookable"
  end

  def down
    remove_index :webhook_logs, name: "index_webhook_logs_on_webhookable" rescue nil
    remove_column :webhook_logs, :webhookable_id
    add_column :webhook_logs, :webhookable_id, :bigint, null: false
    add_index :webhook_logs, [ :webhookable_type, :webhookable_id ], name: "index_webhook_logs_on_webhookable"
  end
end
