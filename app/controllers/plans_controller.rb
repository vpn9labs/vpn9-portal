class PlansController < ApplicationController
  allow_unauthenticated_access only: [ :index, :show ]

  def index
    @plans = Plan.active.order(:price)
  end

  def show
    @plan = Plan.active.find(params[:id])

    if authenticated?
      # Show payment options for authenticated users
      @available_cryptos = fetch_available_cryptos
    else
      # Redirect to signup/login for unauthenticated users
      session[:return_to_after_authenticating] = plan_path(@plan)
      redirect_to new_session_path, notice: "Please sign in to purchase a subscription"
    end
  end

  private

  def fetch_available_cryptos
    PaymentProcessor.available_cryptos
  end
end
