json.countries do
  json.array! @countries.keys.sort do |country_code|
    locations = @countries[country_code]

    # Use the first location to get country name
    first_location = locations.first

    json.name first_location.country_name
    json.code country_code.downcase

    json.cities do
      json.array! locations.sort_by(&:city) do |location|
        json.name location.city
        json.code location.city_code
        json.latitude location.latitude
        json.longitude location.longitude

        json.relays do
          json.array! location.relays.active.order(:name) do |relay|
            json.hostname relay.hostname
            json.ipv4_addr_in relay.ipv4_address
            json.ipv6_addr_in relay.ipv6_address if relay.ipv6_address.present?
            json.public_key relay.public_key
            json.multihop_port relay.port
          end
        end
      end
    end
  end
end
