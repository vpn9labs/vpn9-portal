class CreateWebhookLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_logs do |t|
      t.references :webhookable, polymorphic: true, null: false
      t.string :ip_address, null: false
      t.string :status, null: true
      t.timestamp :processed_at
      t.timestamps
    end
  end
end
