class WebhookLog < ApplicationRecord
  belongs_to :webhookable, polymorphic: true
end
