class Api::V1::RelaysController < Api::BaseController
  # GET /api/v1/relays
  # Return list of available relays - NO tracking of which relay user connects to
  def index
    # Group relays by country for the view
    @countries = Relay.active
                      .includes(:location)
                      .group_by { |relay| relay.location.country_code }
                      .transform_values { |relays| relays.map(&:location).uniq }

    # The response is rendered via app/views/api/v1/relays/index.json.jbuilder
  end
end
