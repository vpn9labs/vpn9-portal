class Api::V1::DevicesController < Api::BaseController
  before_action :ensure_can_add_device

  rescue_from ActionController::ParameterMissing, with: :handle_missing_parameter

  # POST /api/v1/devices
  # Register a new WireGuard device for the authenticated user.
  def create
    relay = find_relay
    return unless relay

    device = current_user.devices.build(device_params)

    if device.save
      DeviceRegistry.set_preferred_relay(device.id, relay.id)

      render json: build_response(device, relay), status: :created
    else
      render json: { errors: device.errors.full_messages }, status: :unprocessable_content
    end
  end

  private

  def ensure_can_add_device
    return if current_user.can_add_device?

    render json: {
      error: "Device limit reached",
      device_limit: current_user.device_limit,
      devices_registered: current_user.devices.count
    }, status: :unprocessable_content
  end

  def device_params
    params.require(:device).permit(:public_key, :name)
  end

  def find_relay
    relay_identifier = params[:relay_id] || params.dig(:device, :relay_id)

    unless relay_identifier.present?
      render json: { error: "relay_id is required" }, status: :unprocessable_content
      return nil
    end

    Relay.active.find(relay_identifier)
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Relay not found or inactive" }, status: :not_found
    nil
  end

  def build_response(device, relay)
    {
      device: {
        id: device.id,
        name: device.name,
        public_key: device.public_key,
        status: device.status,
        ipv4: device.ipv4_address,
        ipv6: device.ipv6_address,
        allowed_ips: device.wireguard_addresses,
        created_at: device.created_at.iso8601
      },
      relay: {
        id: relay.id,
        name: relay.name,
        hostname: relay.hostname,
        public_key: relay.public_key,
        port: relay.port,
        location: relay.location&.city,
        country_code: relay.location&.country_code
      }
    }
  end

  def handle_missing_parameter(exception)
    render json: { error: exception.message }, status: :bad_request
  end
end
