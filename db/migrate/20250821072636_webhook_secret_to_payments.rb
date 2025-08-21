class WebhookSecretToPayments < ActiveRecord::Migration[8.0]
  def change
    add_column :payments, :webhook_secret, :string
  end
end
