class DeviceSetupController < ApplicationController
  before_action :check_device_limit, only: [ :new ]

  def new
    # Step 1: Key generation and location selection
    @locations = Location.joins(:relays).where(relays: { status: :active }).distinct
  end

  def create
    # Create device with public key and generate config
    @device = Current.user.devices.build(device_params)

    if @device.save
      @relay = Relay.find(params[:relay_id])
      @private_key = params[:private_key] # From client-side, never stored

      # Generate config with the selected relay
      config_service = WireguardConfigService.new(device: @device, relay: @relay)
      @config_content = generate_complete_config(config_service, @private_key)

      # Return config as downloadable file
      send_data @config_content,
                filename: "vpn9-#{@device.name}.conf",
                type: "text/plain",
                disposition: "attachment"
    else
      @locations = Location.joins(:relays).where(relays: { status: :active }).distinct
      render :new, status: :unprocessable_content
    end
  end

  def locations
    # AJAX endpoint to get locations with active relays
    @locations = Location.joins(:relays)
                        .where(relays: { status: :active })
                        .distinct
                        .select(:id, :city, :country_code)

    render json: @locations.map { |loc|
      {
        id: loc.id,
        name: loc.city,
        country: loc.country_name,
        city: loc.city,
        display_name: "#{loc.city}, #{loc.country_name}"
      }
    }
  end

  def relays
    # AJAX endpoint to get relays for a specific location
    location = Location.find(params[:location_id])
    @relays = location.relays.active

    render json: @relays.map { |relay|
      {
        id: relay.id,
        name: relay.name,
        hostname: relay.hostname,
        public_key: relay.public_key,
        port: relay.port,
        load: relay_load_status(relay)
      }
    }
  end

  private

  def check_device_limit
    unless Current.user.can_add_device?
      redirect_to devices_path, alert: "You have reached your device limit of #{Current.user.device_limit} devices"
    end
  end

  def device_params
    params.require(:device).permit(:public_key)
  end

  def generate_complete_config(config_service, private_key)
    # Generate config with actual private key (not stored on server)
    config_service.generate_client_config(include_private_key: true, private_key: private_key)
  end

  def relay_load_status(relay)
    # In production, this would check actual relay load
    # For now, return a mock status
    %w[low medium high].sample
  end
end
