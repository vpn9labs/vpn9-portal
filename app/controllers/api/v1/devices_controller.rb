class Api::V1::DevicesController < Api::BaseController
  before_action :ensure_can_add_device, only: :create

  rescue_from ActionController::ParameterMissing, with: :handle_missing_parameter

  # POST /api/v1/devices
  # Register a new WireGuard device for the authenticated user.
  def create
    device = current_user.devices.build(device_params)

    if device.save
      render json: build_response(device), status: :created
    else
      render json: { errors: device.errors.full_messages }, status: :unprocessable_content
    end
  end

  # POST /api/v1/devices/verify
  # Verify an existing device belongs to the authenticated user.
  def verify
    device = current_user.devices.find_by(public_key: extract_public_key_param)

    unless device
      render json: { error: "Device not found" }, status: :not_found
      return
    end

    render json: build_response(device), status: :ok
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
    params.require(:device).permit(:public_key)
  end

  def handle_missing_parameter(exception)
    render json: { error: exception.message }, status: :bad_request
  end

  def device_payload(device)
    {
      id: device.id,
      name: device.name,
      public_key: device.public_key,
      status: device.status,
      ipv4: device.ipv4_address,
      ipv6: device.ipv6_address,
      allowed_ips: device.wireguard_addresses,
      created_at: device.created_at&.iso8601
    }
  end

  def build_response(device)
    { device: device_payload(device) }
  end

  def extract_public_key_param
    public_key = params[:public_key] || params.dig(:device, :public_key)
    return public_key if public_key.present?

    raise ActionController::ParameterMissing, :public_key
  end
end
