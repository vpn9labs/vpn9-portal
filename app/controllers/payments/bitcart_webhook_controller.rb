module Payments
  # Receives Bitcart payment status webhooks. API-only controller (no CSRF).
  class BitcartWebhookController < ActionController::API
    # POST /payments/webhook
    def create
      payment_id = params[:external_id] || params[:order_id]
      payment = Payment.find_by(id: payment_id)

      unless payment
        Rails.logger.warn "Webhook received for unknown payment: #{payment_id}"
        head :not_found
        return
      end

      if payment.webhook_secret.present?
        unless ActiveSupport::SecurityUtils.secure_compare(
                 params[:secret].to_s,
                 payment.webhook_secret.to_s
               )
          head :unauthorized
          return
        end
      end

      # Ensure we pass a plain hash to model update method
      payment.update_from_webhook!(params.to_unsafe_h, request.remote_ip)
      head :ok
    rescue => e
      Rails.logger.error "Webhook processing failed: #{e.message}"
      head :internal_server_error
    end
  end
end
