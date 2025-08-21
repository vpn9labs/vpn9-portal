class PaymentsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :webhook
  allow_unauthenticated_access only: :webhook

  before_action :set_plan, only: [ :new, :create ]

  def new
    @payment = Current.user.payments.build(plan: @plan)
    @crypto = params[:crypto] || "btc"
  end

  def create
    @crypto = params[:crypto]

    # Create payment record
    @payment = Current.user.payments.build(
      plan: @plan,
      amount: @plan.price,
      currency: @plan.currency,
      crypto_currency: @crypto,
      expires_at: 1.hour.from_now
    )

    if @payment.save
      # Create payment request with payment processor
      begin
        response = PaymentProcessor.create_payment(@crypto, @payment, @plan)

        Rails.logger.info "Payment processor response: #{response.inspect}"

        # Update payment with processor details
        # If the actual currency is different (e.g., USDT instead of ETH), update it
        actual_currency = response["actual_currency"] || @crypto

        @payment.update!(
          processor_id: response["id"],
          payment_address: response["wallet"],
          crypto_amount: response["amount"],
          crypto_currency: actual_currency.downcase,
          processor_data: response
        )

        Rails.logger.info "Payment saved with address: #{@payment.payment_address}"

        redirect_to payment_path(@payment)
      rescue => e
        @payment.destroy
        redirect_to plan_path(@plan), alert: "Unable to create payment: #{e.message}"
      end
    else
      redirect_to plan_path(@plan), alert: "Unable to create payment record"
    end
  end

  def show
    @payment = Current.user.payments.find(params[:id])

    # Check payment status if still pending
    if @payment.pending? && @payment.processor_id.present?
      begin
        status = PaymentProcessor.get_payment_status(@payment.crypto_currency, @payment.processor_id)

        if status && status["status"] != "UNPAID"
          @payment.update_status!(status["status"])
        end
      rescue ::BitcartClient::Error => e
        Rails.logger.error "Failed to check payment status: #{e.message}"
        # Continue showing the payment page even if status check fails
      end
    end

    # Redirect to subscription page if payment is complete
    if @payment.successful?
      redirect_to subscriptions_path, notice: "Payment completed successfully!"
    end
  end

  def webhook
    # Verify webhook authenticity if needed
    # Payment processors send payment status updates here

    payment_id = params[:external_id] || params[:order_id]
    payment = Payment.find_by(id: payment_id)

    # If payment does not exist, return 404
    unless payment
      Rails.logger.warn "Webhook received for unknown payment: #{payment_id}"
      head :not_found
      return
    end

    # Verify webhook authenticity when a secret is set
    if payment.webhook_secret.present?
      unless ActiveSupport::SecurityUtils.secure_compare(
        params[:secret].to_s,
        payment.webhook_secret.to_s
      )
        head :unauthorized
        return
      end
    end

    # Update payment status
    payment.update_from_webhook!(params, request.remote_ip)
    head :ok
  rescue => e
    Rails.logger.error "Webhook processing failed: #{e.message}"
    head :internal_server_error
  end

  private

  def set_plan
    @plan = Plan.active.find(params[:plan_id])
  end
end
