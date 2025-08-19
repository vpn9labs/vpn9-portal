class Admin::RelaysController < Admin::BaseController
  before_action :set_relay, only: [ :show, :edit, :update, :destroy ]

  def index
    @relays = Relay.includes(:location).order(:name)
  end

  def show
  end

  def new
    @relay = Relay.new
    @locations = Location.order(:city, :country_code)
  end

  def edit
    @locations = Location.order(:city, :country_code)
  end

  def create
    @relay = Relay.new(relay_params)

    if @relay.save
      redirect_to admin_relay_path(@relay), notice: "Relay was successfully created."
    else
      @locations = Location.order(:city, :country_code)
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @relay.update(relay_params)
      redirect_to admin_relay_path(@relay), notice: "Relay was successfully updated."
    else
      @locations = Location.order(:city, :country_code)
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @relay.destroy
    redirect_to admin_relays_path, notice: "Relay was successfully deleted."
  end

  private

  def set_relay
    @relay = Relay.find(params[:id])
  end

  def relay_params
    params.require(:relay).permit(:name, :hostname, :ipv4_address, :ipv6_address,
                                   :public_key, :port, :status, :location_id)
  end
end
